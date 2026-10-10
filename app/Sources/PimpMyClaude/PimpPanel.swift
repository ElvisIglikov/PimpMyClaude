import AppKit
import ClaudeAX
import SwiftUI

// Вылетающая панель у часов (WF87; с WF126 — по макету 1.5, `docs/wf126-spec.md`): стекло, неактивирующая,
// фокус остаётся у Claude. Решения (что показывать и какими словами) — в `PimpPanelText`, `PanelProjects`
// и `StatusIcon` (ClaudeAX, тесты `PanelWF87Tests`, `PanelProjectsTests`); здесь вид и окно.

/// Пружины центра Диктатора (`CenterSpring`): жёсткость / затухание при массе 1.
enum PanelSpring {
    static func make(_ stiffness: Double, _ damping: Double) -> Animation {
        .spring(response: 2 * .pi / stiffness.squareRoot(), dampingFraction: damping / (2 * stiffness.squareRoot()))
    }
    static let pop = make(560, 25)
    static let settings = make(400, 27)
    static let roll = make(380, 23)
    static let press = make(900, 21)
    static let gather = Animation.timingCurve(0.55, 0, 0.85, 0.35, duration: 0.22)
}

enum PanelColor {
    static func hex(_ value: UInt32, _ alpha: Double = 1) -> Color {
        Color(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255, opacity: alpha)
    }
    /// «#0f2e22» из палитры темы; не разобрали — цвет «как у Claude».
    static func css(_ value: String) -> Color {
        hex(UInt32(value.trimmingCharacters(in: CharacterSet(charactersIn: "# ")), radix: 16) ?? 0x2B2A27)
    }
    // Графит (WF103, DESIGN.md): серые фон, линии и текст; акцент с WF126 выбирается (`pmpAccent`).
    static let text = hex(0xECECEE)
    static let sub = hex(0x9B9BA1)
    static let good = hex(0x5FB884)
    static let bad = hex(0xD9695F)
    static let warn = hex(0xEFC65C)
    static let ink = hex(0x1C1C1E)
    static let frame = hex(0x3A3A3D)
    static let panel = hex(0x262628)
    static let danger = hex(0xEEA39E)
}

/// Акцент PMP из окружения: ставит `PanelRoot` (выбор или примерка наведением).
private struct AccentKey: EnvironmentKey {
    static let defaultValue = PanelColor.hex(PMPAccent.violet.hex)
}

extension EnvironmentValues {
    var pmpAccent: Color {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
}

/// Выключатель в сетке по два в ряд.
struct PanelToggle: Identifiable, Equatable {
    let id: String
    let title: String
    let on: Bool
    /// Без Универсального доступа — жёлтое «нужен доступ» вместо переключателя.
    let needsAccess: Bool
    let toolTip: String
    var mixed = false
}

/// Что делает кнопка патча: ничего, идёт (текст шага), сорвалось (причина).
enum PatchRun: Equatable {
    case idle
    case running(String)
    case failed(String)
}

/// Строка «Поставить Рика» в настройках (WF216, #9381): нет строки (папка Rick есть), покой, идёт, готово, ошибка.
enum RickInstall: Equatable {
    case hidden
    case idle
    case running
    case done(String)
    case failed(String)

    /// Итог копирования → вид строки; путь — с «~», как человек его видит в Finder.
    init(_ outcome: RickKit.Outcome) {
        switch outcome {
        case .installed(let folder), .exists(let folder):
            self = .done(NSString(string: folder.path).abbreviatingWithTildeInPath)
        case .failed(let why): self = .failed(why)
        }
    }

    /// Чем Рик полезен — одной фразой под кнопкой; при ошибке — что случилось, что уцелело и что нажать.
    var caption: String {
        if case .failed(let why) = self { return "Рик не встал: \(why). Ничего не изменилось — нажми ещё раз." }
        return "Главный чат: ведёт остальные проекты и Workflow."
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// Нажатия панели — их разводит `AppDelegate` и `PanelFeed`.
struct PanelActions {
    var patch: () -> Void = {}
    var findClaude: () -> Void = {}
    var patchLog: () -> Void = {}
    var download: () -> Void = {}
    var update: () -> Void = {}
    var updateAnyway: () -> Void = {}
    var wait: () -> Void = {}
    var updateNow: () -> Void = {}
    var later: () -> Void = {}
    var cancelRace: () -> Void = {}
    var retryUpdate: () -> Void = {}
    var toggle: (String) -> Void = { _ in }
    var sendDelay: (_ on: Bool, _ seconds: Int) -> Void = { _, _ in }
    var previewSendDelay: (_ seconds: Int) -> Void = { _ in }
    /// Группа «Закреплённые» (#8743): название проекта и таймер у закреплённых чатов.
    var pinnedLook: (PinnedLook) -> Void = { _ in }
    /// «Бэкап чатов» (#7729, WF94): все чаты Claude Code одним zip на склад.
    var archiveChats: () -> Void = {}
    /// «PimpViewer» (WF97): лента всех HTML и фото чатов.
    var showViewer: () -> Void = {}
    /// «Поставить Рика» и «Показать в Finder» (WF216).
    var installRick: () -> Void = {}
    var revealRick: () -> Void = {}
    /// «Обновлять Пимп и Viewer самим» (WF217, К-SU).
    var selfUpdate: (Bool) -> Void = { _ in }
    var setup: () -> Void = {}
    /// «Поддержать автора» (WF108, #8179): окно и выключатель «Показывать „Поддержать“» в настройках.
    var donate: () -> Void = {}
    var toggleDonate: () -> Void = {}
    var about: () -> Void = {}
    var uninstall: () -> Void = {}
    var quit: () -> Void = {}
    // WF126: цвета.
    var windowColor: (WindowColorChoice) -> Void = { _ in }
    var previewWindowColor: (WindowColorChoice?) -> Void = { _ in }
    /// Переключатель «Живой» блока «Оформление» (WF180): живой фон в тонах цвета окон или тот же цвет статично.
    var live: (Bool) -> Void = { _ in }
    var setAccent: (PMPAccent) -> Void = { _ in }
    /// Esc: true — обработан (отсчёт, поле, лист настроек), панель остаётся.
    var escape: () -> Bool = { false }
    // WF126 §7: лист «Настройки».
    var enterKeys: (EnterKeys) -> Void = { _ in }
    /// Звук отсчёта (WF151): пункт подменю «🔊 Звук отсчёта ▸».
    var countdownSound: (CountdownSound) -> Void = { _ in }
    /// Вид отсчёта (К1 v3, #9041): пункт подменю «🚀 Вид отсчёта ▸».
    var sendLookStyle: (String) -> Void = { _ in }
    var bypassNew: (Bool) -> Void = { _ in }
    /// Блок «Текст» (WF167, #9168): по ширине (true) или влево; поля по бокам 0…40.
    var textJustify: (Bool) -> Void = { _ in }
    var sidePadding: (Int) -> Void = { _ in }
    /// «Чистые ответы» (WF210, #9398, К-CA): строки расхода и состояния под ответами спрятаны.
    var cleanAnswers: (Bool) -> Void = { _ in }
    var openClaudeSettings: () -> Void = {}
    /// Вариант значка (WF180): одна картинка из нескольких.
    var iconVariant: (StatusIcon.Variant) -> Void = { _ in }
}

/// Группа листа «Настройки» (§7): открыта всегда одна.
enum SettingsGroup { case text, enter, chats, pinned, windows, updates, more }

final class PanelModel: ObservableObject {
    enum Phase { case folded, popped, open }
    /// Лист панели: сама панель или «Настройки» за шестерёнкой (§7).
    enum Sheet { case panel, settings }

    @Published var phase = Phase.folded
    @Published var sheet = Sheet.panel
    @Published var patch: StatusIcon.Patch = .unknown
    @Published var limits: ClaudeLimits?
    @Published var update: PimpPanelText.UpdateBlock = .none
    @Published var readySize: String?
    @Published var raceStartedAt: Date?
    @Published var lanes = LaneMemory()
    @Published var toggles: [PanelToggle] = []
    @Published var sendDelay = SendDelaySetting()
    @Published var sendDelayLine: String?
    @Published var pinnedLook = PinnedLook()
    @Published var maxCardHeight: CGFloat = 800
    @Published var patchRun = PatchRun.idle
    /// Найденную версию PMP уже отказался ставить (второй замок Electron, G2 WF101): блок
    /// «доступна» пишет «PimpMyClaude пока не патчит Claude X» без кнопки «Скачать».
    @Published var refusedVersion: String?
    /// Бэкап чатов собирается (WF97 Б5s, #7772): строка «Бэкап чатов — идёт…», нажатия нет.
    @Published var archiving = false
    @Published var rick = RickInstall.hidden
    /// Автообновление Пимпа и Viewer (WF217, К-SU): переключатель, тихая строка под ним и строка «обновился».
    @Published var selfUpdate = SelfUpdateDriver.Look()
    @Published var now = Date()
    /// Где по X у панели значок — туда светится верхняя кромка и оттуда вылет.
    @Published var anchorX: CGFloat = 170
    /// «Поддержать автора» (WF108): окну есть что показать (иначе нет ни строки, ни выключателя)
    /// и показывать ли пункт в меню окна.
    @Published var donateAvailable = false
    @Published var donateShown = true
    // WF126
    @Published var accent = PMPAccent.current
    @Published var accentPreview: PMPAccent?
    /// Снимок проектов; nil — ещё не читали («Читаю проекты…»).
    @Published var projects: PanelSnapshot?
    @Published var windowThemes: [WindowColorChip] = []
    /// Все темы каталога — имя выбранной не из десяти в строке «Цвет Claude» (#9040).
    @Published var allThemes: [WindowColorChip] = []
    /// «Цвет Claude» раскрыт (WF141, #9114): по умолчанию свёрнут в строку, выбор помнится (`PanelColorTiles.openKey`).
    @Published var colorsOpen = PanelColorTiles.isOpen()
    /// Живой фон всем окнам включён (слой `look.aurora` scope `all`).
    @Published var liveBackground = false
    /// Схема живого фона всем окнам (`LookScheme`, WF145); нет ключа — умолчание.
    @Published var liveScheme = LookScheme.defaultID
    /// Выбор цвета PMP под шапкой — нажатием на значок слева вверху (#9020 п. 3–5).
    @Published var accentOpen = false
    /// Вид значка у часов — тот же значок в шапке панели.
    @Published var iconLook: StatusIcon.Look?
    @Published var windowColor = WindowColorChoice.byProject
    /// Тема всем окнам не из шести кружков (выбрана в меню жёлтой кнопки) — её имя для подписи.
    @Published var foreignTheme: String?
    @Published var settingsGroup: SettingsGroup?
    @Published var enterKeys = EnterKeys()
    @Published var countdownSound = CountdownSound.fallback
    @Published var sendLookStyle = SendLook.defaultStyle
    @Published var bypassNew = false
    @Published var textJustify = TextLook.justifyDefault
    @Published var sidePadding = 24
    @Published var cleanAnswers = CleanAnswers.defaultOn
    @Published var bypassPermission = BypassNew.Permission.unknown
    /// Пункт «Settings…» Claude не нашёлся — ссылка говорит, где он.
    @Published var claudeSettingsFailed = false
    /// Температура Мака за 3 ч (#8898); пусто — строки нет (выключено или датчики молчат).
    @Published var temperature: [MacTemperatureSample] = []
    @Published var temperatureOpen = false
    /// Нагрузка на память за 3 ч (#9082, WF164); пусто — плитки нет. Приходит, только пока панель открыта.
    @Published var memory: [MacMemorySample] = []
    @Published var memoryOpen = false
    /// Токены за 7 дней по копилке Рика (WF157, #9149; WF170 — несобранный день nil); nil — файла нет, плитки нет.
    @Published var tokenSpark: TokenSpark?
    /// Плитка «Токены» — окно с графиком рядом с панелью.
    var openTokens: () -> Void = {}
    /// Блоки-виджеты (WF129, #9043): порядок и ширина, перетаскивание; «Workflow списком» раскрыт.
    @Published var layout = PanelWidgetLayout.load()
    @Published var widgetDrag: PanelWidgetDrag?
    /// Чей заголовок сейчас показывает значки управления (WF187, #9247) — один блок за раз.
    @Published var widgetChrome: String?
    /// Вариант значка (WF180; до того WF129 — проекты, WF174 — три выключателя).
    @Published var iconVariant = StatusIcon.variant()
    var loader = 7
    /// Высота карточки — клик по тени и пустому холсту тоже «мимо».
    var cardHeight: CGFloat = 44
    var appVersion = ""
    var reduceMotion = false
    var actions = PanelActions()
    let teamPulls = TeamPulls()

    var fresh: ClaudeLimits? { StatusIcon.isFresh(limits, now: now) ? limits : nil }
    var shownAccent: PMPAccent { accentPreview ?? accent }

    /// Указатель с перетаскиваемым блоком над `hit` (чужим блоком или nil): блок встаёт на его место.
    func dragWidget(_ id: String, over hit: String?) {
        if widgetDrag == nil { widgetDrag = PanelWidgetDrag(id: id, before: layout) }
        guard var drag = widgetDrag, drag.id == id else { return }
        let next = drag.step(over: hit, in: layout)
        widgetDrag = drag
        guard let moved = next else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : PanelSpring.settings) { layout = moved }
    }

    /// Отпустили мышь (или жест сорвался): раскладка запоминается, если не отменили Esc.
    func endWidgetDrag() {
        guard let drag = widgetDrag else { return }
        widgetDrag = nil
        if !drag.cancelled { layout.save() }
    }

    /// Esc во время перетаскивания: порядок — как до него. true — было что отменять.
    func cancelWidgetDrag() -> Bool {
        guard var drag = widgetDrag, !drag.cancelled else { return false }
        drag.cancelled = true
        widgetDrag = drag
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : PanelSpring.settings) { layout = drag.before }
        return true
    }

    /// «Шире» / «Уже» и «Вернуть как было».
    func changeLayout(_ change: (inout PanelWidgetLayout) -> Void) {
        var next = layout
        change(&next)
        guard next != layout else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : PanelSpring.settings) { layout = next }
        next.save()
    }
}

// MARK: - окно

final class PimpPanelController {
    static let width: CGFloat = 340
    /// Запас холста под тень и свечение по бокам.
    static let margin: CGFloat = 48

    let model = PanelModel()
    /// Окно «Токены по проектам» (WF157) — рядом с карточкой.
    let tokens = TokensWindowController()
    private var window: PimpPanelWindow?
    private weak var button: NSStatusBarButton?
    private var monitors: [Any] = []
    private var timer: Timer?
    private var openedAt: TimeInterval = 0
    private var generation = 0
    private(set) var isOpen = false
    private var closedAt: TimeInterval = -.infinity
    /// Закрыта меньше секунды назад: запрос «открыть» из окна Claude (#8894) — тот же клик, что её закрыл.
    var closedJustNow: Bool { !isOpen && ProcessInfo.processInfo.systemUptime - closedAt < 1 }
    /// Панель открылась — свежие данные (статус патча, проверка обновления).
    var onOpen: () -> Void = {}
    /// Панель закрылась — вопрос блока обновления снимается (гейт 2 WF87).
    var onClose: () -> Void = {}

    func toggle(from button: NSStatusBarButton) {
        isOpen ? close() : open(from: button)
    }

    func open(from button: NSStatusBarButton) {
        guard let barWindow = button.window else { return }
        generation += 1
        let generation = generation
        self.button = button
        isOpen = true
        let screen = barWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 875)
        let top = barWindow.frame.minY - 5
        let center = barWindow.frame.midX
        let x = min(max(center - Self.width / 2, visible.minX + 8), visible.maxX - 8 - Self.width)
        let canvas = NSRect(x: x - Self.margin, y: visible.minY, width: Self.width + Self.margin * 2,
                            height: max(200, top - visible.minY))
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            model.maxCardHeight = canvas.height
            model.cardHeight = min(model.cardHeight, canvas.height)
            model.phase = .folded
            model.sheet = .panel
            model.settingsGroup = nil
            model.accentOpen = false
            model.now = Date()
            model.anchorX = min(max(center - x, 24), Self.width - 24)
            model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
        onOpen()
        model.openTokens = { [weak self] in self?.showTokens() }
        tokens.spark { [weak self] values in self?.model.tokenSpark = values }
        let window = self.window ?? makeWindow()
        self.window = window
        window.setFrame(canvas, display: true)
        window.alphaValue = 1
        window.orderFrontRegardless()
        // Ключевое окно — ради Esc и поля «Ответить…» (ловим только у себя: глобальный монитор донёс бы
        // Esc до Claude и остановил бы чат Claude Code). Приложение при этом не активируется.
        window.makeKey()
        button.highlight(true)
        openedAt = ProcessInfo.processInfo.systemUptime
        startWatching()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) { [weak self] in
            guard let self = self, generation == self.generation, self.isOpen else { return }
            if self.model.reduceMotion {
                withAnimation(.easeOut(duration: 0.15)) { self.model.phase = .open }
                return
            }
            withAnimation(PanelSpring.pop) { self.model.phase = .popped }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
                guard generation == self.generation, self.isOpen else { return }
                withAnimation(PanelSpring.settings) { self.model.phase = .open }
            }
        }
    }

    func close() {
        guard isOpen else { return }
        generation += 1
        let generation = generation
        isOpen = false
        closedAt = ProcessInfo.processInfo.systemUptime
        stopWatching()
        button?.highlight(false)
        if model.widgetDrag != nil { _ = model.cancelWidgetDrag(); model.endWidgetDrag() }
        onClose()
        let finish = { [weak self] in
            guard let self = self, generation == self.generation else { return }
            self.window?.orderOut(nil)
        }
        if model.reduceMotion {
            withAnimation(.easeIn(duration: 0.15)) { model.phase = .folded }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { finish() }
            return
        }
        withAnimation(PanelSpring.gather) { model.phase = .folded }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { finish() }
    }

    /// Высота изменилась (раскрыли «Ещё», пришёл блок обновления) — пружиной settings.
    func change(_ body: () -> Void) {
        withAnimation(model.reduceMotion ? .easeOut(duration: 0.15) : PanelSpring.settings) { body() }
    }

    /// Лист «Настройки» и обратно (шестерёнка, ⌘,, правый клик «Настройки…»).
    func showSheet(_ sheet: PanelModel.Sheet) {
        guard model.sheet != sheet else { return }
        change {
            model.sheet = sheet
            model.settingsGroup = nil
        }
    }

    private func startWatching() {
        stopWatching()
        let tick = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.model.now = Date() }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
        // Клик мимо: в чужом приложении — глобальный монитор, в своём другом окне — локальный.
        // Клик по самому значку — не «мимо»: его решает `toggle` (как `CenterPanel` Диктатора).
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown],
                                                          handler: { [weak self] _ in self?.clickedOutside() }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: {
            [weak self] event in
            guard let self = self else { return event }
            if event.window === self.window {
                if !self.cardContains(event.locationInWindow) { self.clickedOutside() }
            } else if !Self.isStatusItem(event.window) && !TokensWindowController.owns(event.window) {
                self.clickedOutside()
            }
            return event
        }) { monitors.append(local) }
    }

    private func stopWatching() {
        timer?.invalidate()
        timer = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    /// Точка окна (снизу вверх) внутри карточки: холст выше её прижат к верху, по бокам — запас.
    private func cardContains(_ point: NSPoint) -> Bool {
        guard let height = window?.frame.height else { return false }
        return point.x >= Self.margin && point.x <= Self.margin + Self.width
            && point.y <= height && point.y >= height - model.cardHeight
    }

    /// Плитка «Токены»: окно слева от карточки (нет места — справа), верх вровень с ней.
    private func showTokens() {
        guard let window = window else { return }
        let frame = window.frame
        let card = NSRect(x: frame.minX + Self.margin, y: frame.maxY - model.cardHeight,
                          width: Self.width, height: model.cardHeight)
        tokens.show(beside: card, screen: window.screen)
    }

    static func isStatusItem(_ window: NSWindow?) -> Bool {
        window.map { String(describing: type(of: $0)).hasPrefix("NSStatusBar") } ?? false
    }

    private func clickedOutside() {
        // Щелчок, которым панель открыли, — ещё не «мимо».
        guard ProcessInfo.processInfo.systemUptime - openedAt > 0.15 else { return }
        close()
    }

    private func makeWindow() -> PimpPanelWindow {
        let window = PimpPanelWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
                                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .popUpMenu
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.onEscape = { [weak self] in
            guard let self = self, !self.model.cancelWidgetDrag(), !self.model.actions.escape() else { return }
            self.close()
        }
        window.onQuit = { [weak self] in self?.model.actions.quit() }
        window.onSettings = { [weak self] in
            guard let self = self else { return }
            self.showSheet(self.model.sheet == .settings ? .panel : .settings)
        }
        let hosting = PanelHostingView(rootView: PanelRoot(model: model))
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        return window
    }
}

final class PimpPanelWindow: NSPanel {
    var onEscape: () -> Void = {}
    var onQuit: () -> Void = {}
    var onSettings: () -> Void = {}
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override func cancelOperation(_ sender: Any?) { onEscape() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape() } else { super.keyDown(with: event) }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            switch event.charactersIgnoringModifiers {
            case "q":
                onQuit()
                return true
            case ",":
                onSettings()
                return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Первое нажатие по неактивной панели — уже действие.
private final class PanelHostingView: NSHostingView<PanelRoot> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - холст

private struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct PanelRoot: View {
    @ObservedObject var model: PanelModel
    @State private var contentHeight: CGFloat = 44

    var body: some View {
        let open = model.phase == .open
        let shown = model.phase != .folded
        let height = open ? min(contentHeight, model.maxCardHeight) : 44
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                PanelBackground(anchorX: model.anchorX)
                    .frame(width: PimpPanelController.width, height: height)
                // WF210 (#9379 п. 1–2; слово Элвиса 10.10.2026: «когда вниз сдвигается оформление. Он прямо дёргается»):
                // полосы прокрутки нет. При системной настройке «показывать всегда» (мышь) она отнимала у содержимого
                // 15 pt: содержимое шириной ровно в панель съезжало влево на половину этого и резалось — и постоянно,
                // когда панель выше экрана, и рывком на время любого раскрытия (содержимое уже выросло, карточка ещё
                // догоняет). Теперь ширина содержимого от настройки macOS не зависит; колесо и жест листают как раньше.
                // Блок шире панели прижат к левому краю, а не к середине: левое поле цело в любом случае.
                ScrollView(.vertical, showsIndicators: false) {
                    PanelContent(model: model)
                        .frame(width: PimpPanelController.width, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: HeightKey.self, value: proxy.size.height)
                        })
                }
                    .frame(width: PimpPanelController.width, height: height, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .scaleEffect(shown ? 1 : (model.reduceMotion ? 1 : 0.94), anchor: UnitPoint(
                x: model.anchorX / PimpPanelController.width, y: 0))
            .opacity(shown ? 1 : 0)
            .padding(.horizontal, PimpPanelController.margin)
            Spacer(minLength: 0)
        }
        .onPreferenceChange(HeightKey.self) { value in
            guard value > 0, abs(value - contentHeight) > 0.5 else { return }
            model.cardHeight = min(value, model.maxCardHeight)
            if model.phase == .open {
                withAnimation(model.reduceMotion ? .easeOut(duration: 0.15) : PanelSpring.settings) {
                    contentHeight = value
                }
            } else {
                contentHeight = value
            }
        }
        .onChange(of: model.maxCardHeight) { value in model.cardHeight = min(contentHeight, value) }
        .environment(\.colorScheme, .dark)
        .environment(\.pmpAccent, PanelColor.hex(model.shownAccent.hex))
    }
}

/// Графитовая подложка, обводка, блик по верху и тень холста — без градиента и свечения (WF103). С WF177 (#9192,
/// слово Элвиса 09.10 02:35: всё просвечивает, ничего не разобрать — «сделай, чтоб не просвечивала») подложка сплошная:
/// без стекла `.hudWindow` и без 6 % просвета — рабочий стол и окна под панелью не видны ни в светлой, ни в тёмной теме.
private struct PanelBackground: View {
    let anchorX: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        ZStack(alignment: .topLeading) {
            shape.fill(PanelColor.ink)
            shape.strokeBorder(PanelColor.frame, lineWidth: 1)
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1).padding(.horizontal, 14)
        }
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.55), radius: 22, y: 18)
    }
}

// MARK: - содержимое

private struct PanelContent: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Header(model: model).appear(0, model)
            // Пимп обновился сам (WF217, К-SU): одна тихая строка при первом открытии панели, без окон и уведомлений.
            if let note = model.selfUpdate.note {
                Text(note).font(.system(size: 11)).foregroundColor(PanelColor.sub).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.sheet == .settings {
                SettingsSheet(model: model).appear(1, model)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                if model.accentOpen {
                    AccentCard(model: model).transition(.opacity.combined(with: .move(edge: .top)))
                }
                if let card = PimpPanelText.patchCard(model.patch) {
                    PatchCardView(model: model, card: card).appear(1, model)
                }
                // Цвет Claude — первым сверху (#9040, #9020 п. 11: «основная наша фишка — цвет Клауда»),
                // подписка под ним (#8958).
                // С WF129 блоки — виджеты (#9043): порядок и ширину выбирает человек; обновление Claude — не
                // виджет, стоит над ними.
                if model.update != .none {
                    UpdateBlockView(model: model).appear(1, model)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                WidgetBoard(model: model, visible: visibleWidgets) { widget in
                    switch widget {
                    case .workflow: WorkflowNowView(model: model)
                    case .colors: ColorsCard(model: model)
                    case .week: MainLimit(model: model)
                    case .limits: LimitTile(model: model, kind: .fiveHour)
                    case .fable: LimitTile(model: model, kind: .fable)
                    case .reset: if let strip = weekStrip { WeekStripView(strip: strip) }
                    case .temperature: TemperatureView(model: model)
                    case .memory: MemoryView(model: model)
                    case .tokens: TokensTile(model: model)
                    }
                }
                // WF171 (#9177): входа «Открыть панель — проекты и Workflow» нет — панель у часов и по кнопке PMP одна
                // и та же, лёгкая. «Идёт Workflow сейчас» с WF214 — обычный виджет (`WorkflowNowView`).
            }
        }
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
    }

    private var weekStrip: StatusIcon.WeekStrip? {
        StatusIcon.weekStrip(StatusIcon.limit(.week, in: model.fresh)?.resetsAt, now: model.now)
    }

    /// Какие виджеты сейчас есть: «Сброс» — когда известен срок, температура — когда датчики отвечают.
    private var visibleWidgets: Set<String> {
        var shown: [PanelWidget] = [.workflow, .colors, .week, .limits]
        // Тариф без Fable (ответ API без поля) — блока нет.
        if !(model.fresh.map { $0.fable == nil && $0.source == "api" } ?? false) { shown.append(.fable) }
        if weekStrip != nil { shown.append(.reset) }
        if let last = model.temperature.last, last.value != nil { shown.append(.temperature) }
        if let last = model.memory.last, last.value != nil { shown.append(.memory) }
        if model.tokenSpark != nil { shown.append(.tokens) }
        return Set(shown.map { $0.rawValue })
    }
}

private struct CardModifier: ViewModifier {
    let radius: CGFloat
    @Environment(\.panelFill) private var fill

    func body(content: Content) -> some View {
        content
            .frame(maxHeight: fill ? .infinity : nil, alignment: .top)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.white.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(PanelColor.frame, lineWidth: 1))
    }
}

/// Блоки сверху вниз: прозрачность 0 → 1, сдвиг −8 и масштаб 0,98 → на место, задержка 60 + 45·i мс.
private struct Appear: ViewModifier {
    let index: Int
    let shown: Bool
    let reduce: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduce ? 0 : -8)
            .scaleEffect(shown || reduce ? 1 : 0.98, anchor: .top)
            .animation(shown ? (reduce ? .easeOut(duration: 0.15)
                                       : PanelSpring.roll.delay(0.06 + 0.045 * Double(index)))
                             : .easeOut(duration: 0.1), value: shown)
    }
}

private extension View {
    func appear(_ index: Int, _ model: PanelModel) -> some View {
        modifier(Appear(index: index, shown: model.phase == .open, reduce: model.reduceMotion))
    }

    /// Карточка: радиус 12, фон белый 4,5 %, рамка 1 px. В сетке виджетов — на всю высоту ряда (`panelFill`).
    func card(radius: CGFloat = 12) -> some View {
        modifier(CardModifier(radius: radius))
    }

    /// Заголовок блока-виджета (WF187): на его место встают значки управления.
    func widgetTitle() -> some View {
        modifier(WidgetTitle())
    }

    /// Над нажимаемым — рука (§1.5).
    func handCursor() -> some View {
        onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
    }
}

/// Нажатие — пружина press (0,97).
private struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(PanelSpring.press, value: configuration.isPressed)
    }
}

/// Кнопка во всю ширину (патч, «Обновить Claude»): 13 полужирный на акценте.
private struct BigButton: View {
    let title: String
    var enabled = true
    let action: () -> Void
    @Environment(\.pmpAccent) private var accent
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PanelColor.ink)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent).brightness(hover && enabled ? 0.08 : 0))
                .opacity(enabled ? 1 : 0.6)
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .onHover { hover = $0 }
    }
}

private struct SmallButton: View {
    let title: String
    var primary = true
    let action: () -> Void
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(primary ? PanelColor.ink : PanelColor.text)
                .padding(.horizontal, 11)
                .frame(minHeight: 26)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(primary ? accent : Color.white.opacity(0.08)))
        }
        .buttonStyle(PressStyle())
    }
}

private struct LinkButton: View {
    let title: String
    var color: Color?
    let action: () -> Void
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 11)).foregroundColor(color ?? accent).underline()
        }
        .buttonStyle(.plain)
    }
}

private struct Badge: View {
    let outlined: Bool
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        Text("PMP")
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundColor(outlined ? accent : PanelColor.ink)
            .frame(width: 32, height: 20)
            .background(shape.fill(outlined ? Color.clear : accent))
            .overlay(shape.strokeBorder(accent, lineWidth: outlined ? 1.2 : 0))
    }
}

/// Кружок «нажми» на углу плашки PMP в шапке (WF189): тихий — цветом подписей; под курсором и при открытом
/// «Цвет PMP» — цветом текста. Вырезан кольцом цвета панели, чтобы не слипался с плашкой.
struct BadgeHint: View {
    static let size: CGFloat = 7
    /// Центр кружка — угол плашки (26; 4,5 от левого верха кнопки 31 × 22): плашка в картинке x 1…24, y 4…18,
    /// у картинки поля по 3 pt.
    static let offset = CGSize(width: -1.5, height: 1)
    /// Запасная плашка `Badge` (32 × 20, до первого `iconLook`; WF193): угол плашки — угол самой вьюхи, центр
    /// кружка — на 1 pt внутрь справа и 0,5 сверху, как у плашки в картинке.
    static let badgeOffset = CGSize(width: 2.5, height: -3)
    let hover: Bool
    let open: Bool
    var offset: CGSize = BadgeHint.offset

    /// Видна ли точка: у плашки-картинки — пока угол не занят меткой беды; у запасной плашки — пока патч не слетел
    /// (тогда рядом красная точка).
    static func shows(_ look: StatusIcon.Look?, patch: StatusIcon.Patch) -> Bool {
        if let look = look { return look.mark == .none }
        if case .lost = patch { return false }
        return true
    }

    var body: some View {
        Circle().fill(hover || open ? PanelColor.text : PanelColor.sub)
            .frame(width: Self.size, height: Self.size)
            .background(Circle().fill(PanelColor.ink).padding(-1.5))
            .offset(offset)
            .animation(.easeOut(duration: 0.15), value: hover)
            .allowsHitTesting(false)
    }
}

private struct Header: View {
    @ObservedObject var model: PanelModel
    @State private var hover = false
    @State private var badgeHover = false

    var body: some View {
        // Одна тонкая строка (#8894): значок, «Max 20x · Claude … · PimpMyClaude …» и шестерёнка настроек (WF126).
        // Точка — только беда (патч слетел); слова о беде — в карточке патча.
        let settings = model.sheet == .settings
        HStack(spacing: 8) {
            // Тот же значок, что у часов (#9020 п. 3–5): нажатие — выбор цвета PMP, смена красит оба.
            Button {
                withAnimation(model.reduceMotion ? .easeOut(duration: 0.15) : PanelSpring.settings) {
                    model.sheet = .panel
                    model.settingsGroup = nil
                    model.accentOpen.toggle()
                }
            } label: {
                // Только значок PMP (WF181, #9217: «Убери „PMP 39“ — зачем дублировать, просто значок отобрази»): полоски,
                // сводка проектов и число — у часов, здесь плашка одна.
                if let look = model.iconLook.map(StatusIcon.badgeOnly) {
                    Image(nsImage: StatusIconArt.image(look, dark: true, accent: model.shownAccent.nsColor))
                        .padding(.horizontal, 3)
                        // «Нажми» (WF189, слово Элвиса 09.10 04:00: «не все догадаются, что на него можно нажать…
                        // кругляшок сверху, как индикатор»): кружок на правом верхнем углу плашки; угол занят меткой
                        // беды — её и видно.
                        .overlay(alignment: .topTrailing) {
                            if BadgeHint.shows(look, patch: model.patch) {
                                BadgeHint(hover: badgeHover, open: model.accentOpen)
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(model.accentOpen ? 0.12 : (badgeHover ? 0.08 : 0))))
                } else {
                    // Та же точка-подсказка, что у плашки-картинки (WF193); беда — красной точкой рядом, без подсказки.
                    Badge(outlined: outlined)
                        .overlay(alignment: .topTrailing) {
                            if BadgeHint.shows(nil, patch: model.patch) {
                                BadgeHint(hover: badgeHover, open: model.accentOpen, offset: BadgeHint.badgeOffset)
                            }
                        }
                }
            }
            .buttonStyle(PressStyle())
            // Плашка — по левой грани карточек (правило №1): подложка наведения выступает за грань, а не значок.
            .padding(.leading, model.iconLook == nil ? 0 : -4)
            .onHover { badgeHover = $0 }
            .handCursor()
            .help("Цвет PMP")
            .accessibilityLabel("Цвет PMP")
            if case .lost = model.patch, model.iconLook == nil { Circle().fill(PanelColor.bad).frame(width: 6, height: 6) }
            Text(PimpPanelText.headerLine(model.patch, plan: model.fresh?.plan, app: model.appVersion))
                .font(.system(size: 11)).foregroundColor(PanelColor.sub).lineLimit(1)
                .minimumScaleFactor(0.8)
                .help(PimpPanelText.headerHelp(model.patch))
            Spacer(minLength: 0)
            Button {
                withAnimation(model.reduceMotion ? .easeOut(duration: 0.15) : PanelSpring.settings) {
                    model.sheet = settings ? .panel : .settings
                    model.settingsGroup = nil
                }
            } label: {
                Image(systemName: "gearshape").font(.system(size: 13))
                    .foregroundColor(hover || settings ? PanelColor.text : PanelColor.sub)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(settings ? 0.12 : (hover ? 0.08 : 0))))
            }
            .buttonStyle(PressStyle())
            .onHover { hover = $0 }
            .handCursor()
            .help("Настройки (⌘,)")
            .accessibilityLabel("Настройки")
        }
        .frame(height: 22)
    }

    /// Бейдж контуром — Claude без патча или не найден (10-choice §3.2).
    private var outlined: Bool {
        switch model.patch {
        case .notInstalled, .claudeNotFound: return true
        default: return false
        }
    }
}

// MARK: виджеты (WF129, #9043)

/// Значки управления блоком (WF187, #9247, слово Элвиса 09.10 03:35: значки, которые скачут туда-сюда, постоянно забирают
/// внимание на себя): не на каждое наведение, а через 0,8 с покоя курсора над заголовком блока; встают на
/// место заголовка (он гаснет), появляются и гаснут за 150 мс.
enum WidgetChrome {
    static let delay: TimeInterval = 0.8
    static let fade: TimeInterval = 0.15
    static let icon = CGSize(width: 16, height: 18)
    static let spacing: CGFloat = 2
    /// Значок в рамке 16 pt по центру: первый сдвинут на 3 pt влево — его грань по грани заголовка.
    static let inset: CGFloat = 3

    enum Step: Equatable { case wait, cancel, hide, keep }

    /// Зона наведения — заголовок блока (не вся карточка) с полями 6 pt; вправо — не уже строки значков, чтобы
    /// курсор, дошедший до крестика, их не гасил. Заголовка нет — зоны нет.
    static func zone(title: CGRect, icons: Int) -> CGRect {
        guard title != .zero, !title.isNull else { return .null }
        let row = CGFloat(icons) * icon.width + CGFloat(max(icons - 1, 0)) * spacing
        let left = title.minX - inset
        let right = max(title.maxX, left + row)
        let top = min(title.minY, title.midY - icon.height / 2)
        let bottom = max(title.maxY, title.midY + icon.height / 2)
        return CGRect(x: left, y: top, width: right - left, height: bottom - top).insetBy(dx: -6, dy: -6)
    }

    /// Что делать, когда курсор вошёл в зону или вышел: вошёл — ждать 0,8 с; ушёл, пока ждали, — не показывать;
    /// ушёл от показанных — гасить.
    static func step(inside: Bool, shown: Bool, waiting: Bool) -> Step {
        if inside { return shown || waiting ? .keep : .wait }
        if shown { return .hide }
        return waiting ? .cancel : .keep
    }
}

/// Рамка заголовка блока в его карточке — туда встают значки управления.
private struct WidgetTitleKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if value == .zero { value = next }
    }
}

private let widgetCellSpace = "pmpWidgetCell"

private struct ChromeShownKey: EnvironmentKey {
    static let defaultValue = false
}

/// Заголовок блока: отдаёт свою рамку значкам управления и гаснет, пока они стоят на его месте.
private struct WidgetTitle: ViewModifier {
    @Environment(\.widgetChromeShown) private var chromeShown

    func body(content: Content) -> some View {
        content
            .opacity(chromeShown ? 0 : 1)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: WidgetTitleKey.self, value: proxy.frame(in: .named(widgetCellSpace)))
            })
    }
}

/// Блок поставлен в одну колонку — его вид ужимается (температура без линии, плитки лимитов столбиком…).
private struct NarrowKey: EnvironmentKey {
    static let defaultValue = false
}

/// Карточка стоит в ряду сетки виджетов: тянется по высоте ряда (WF181, #9217), фон и рамка — на всю высоту.
private struct FillKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var panelNarrow: Bool {
        get { self[NarrowKey.self] }
        set { self[NarrowKey.self] = newValue }
    }

    var panelFill: Bool {
        get { self[FillKey.self] }
        set { self[FillKey.self] = newValue }
    }

    /// Значки управления блоком стоят на месте заголовка (WF187).
    var widgetChromeShown: Bool {
        get { self[ChromeShownKey.self] }
        set { self[ChromeShownKey.self] = newValue }
    }
}

private struct WidgetFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Координаты рамок виджетов и указателя при перетаскивании.
private let widgetSpace = "pmpWidgets"

private struct WidgetIDKey: LayoutValueKey {
    static let defaultValue = ""
}

/// Сетка виджетов: ряды решает `PanelWidgetLayout.rows` (широкий — свой ряд, узкие — по двое), здесь только
/// место. Один `ForEach` с постоянными id — перестановка и смена ширины едут пружиной, состояние блоков живо.
struct WidgetGrid: Layout {
    let rows: [[PanelWidgetLayout.Item]]
    /// Раскрытые графики (температура, память): их ряд не выравнивается — сосед не растягивается пустым.
    var loose: Set<String> = []
    var spacing: CGFloat = 10
    var gap: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? PimpPanelController.width - 24
        return CGSize(width: width, height: place(width, subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = place(bounds.width, subviews)
        for (index, subview) in subviews.enumerated() {
            guard let frame = placed.frames[index] else {
                subview.place(at: bounds.origin, proposal: .zero)
                continue
            }
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    private func place(_ width: CGFloat, _ subviews: Subviews) -> (frames: [Int: CGRect], height: CGFloat) {
        let half = (width - gap) / 2
        let index: (String) -> Int? = { id in subviews.firstIndex { $0[WidgetIDKey.self] == id } }
        let measured = rows.map { row in row.compactMap { item -> (id: String, wide: Bool, height: CGFloat)? in
            guard let at = index(item.id) else { return nil }
            let wide = item.wide || row.count == 1
            let height = subviews[at].sizeThatFits(ProposedViewSize(width: wide ? width : half, height: nil)).height
            return (item.id, wide, height)
        } }
        let placed = Self.frames(measured, width: width, gap: gap, spacing: spacing, loose: loose)
        var frames: [Int: CGRect] = [:]
        for (id, frame) in placed.frames { if let at = index(id) { frames[at] = frame } }
        return (frames, placed.height)
    }

    /// Рамки блоков по рядам. Ряд — одной высоты (WF181, #9217: «по высоте все элементы одинаковые»): по самой
    /// высокой карточке ряда, остальные тянутся до неё. Ряд с раскрытым графиком (`loose`) — каждый своей высоты,
    /// по верху: иначе сосед стоял бы пустой коробкой в высоту графика. Одинокая половинка — во всю ширину (WF187):
    /// пустая вторая половина ряда выглядела дырой.
    static func frames(_ rows: [[(id: String, wide: Bool, height: CGFloat)]], width: CGFloat, gap: CGFloat,
                       spacing: CGFloat, loose: Set<String> = []) -> (frames: [String: CGRect], height: CGFloat) {
        let half = (width - gap) / 2
        var frames: [String: CGRect] = [:]
        var y: CGFloat = 0
        for row in rows where !row.isEmpty {
            let tallest = row.map { $0.height }.max() ?? 0
            var x: CGFloat = 0
            let even = !row.contains { loose.contains($0.id) }
            for item in row {
                let w = item.wide || row.count == 1 ? width : half
                frames[item.id] = CGRect(x: x, y: y, width: w, height: even ? tallest : item.height)
                x += w + gap
            }
            y += tallest + spacing
        }
        return (frames, max(0, y - spacing))
    }
}

/// Виджеты панели: над блоком при наведении — ручка (тащить, Esc — отмена), «во всю ширину · половина» и крестик
/// «скрыть» (WF174, #9182 п. 5); скрытые — строкой «Скрытые: + Fable» под блоками, нажатие возвращает.
private struct WidgetBoard<Cell: View>: View {
    @ObservedObject var model: PanelModel
    let visible: Set<String>
    @ViewBuilder let cell: (PanelWidget) -> Cell
    @State private var frames: [String: CGRect] = [:]

    var body: some View {
        let items = model.layout.items.filter { visible.contains($0.id) && !$0.hidden }
        let hidden = model.layout.hidden(visible: visible)
        VStack(alignment: .leading, spacing: 8) {
            grid(items)
            if !hidden.isEmpty { HiddenWidgetsRow(model: model, items: hidden) }
        }
    }

    private func grid(_ items: [PanelWidgetLayout.Item]) -> some View {
        let rows = model.layout.rows(visible: visible)
        // Половинка без пары (WF187) — во всю ширину; широкий блок своим рядом сюда не входит: его можно сузить.
        let lone = Set(rows.filter { $0.count == 1 }.flatMap { $0 }.filter { !$0.wide }.map { $0.id })
        return WidgetGrid(rows: rows,
                   loose: Set((model.temperatureOpen ? [PanelWidget.temperature.rawValue] : [])
                              + (model.memoryOpen ? [PanelWidget.memory.rawValue] : []))) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if let widget = item.widget {
                    WidgetCell(model: model, item: item, alone: lone.contains(item.id), frames: frames) { cell(widget) }
                        .layoutValue(key: WidgetIDKey.self, value: item.id)
                        .zIndex(model.widgetDrag?.id == item.id ? 1 : 0)
                        .appear(min(1 + index / 2, 3), model)
                }
            }
        }
        .coordinateSpace(name: widgetSpace)
        .onPreferenceChange(WidgetFramesKey.self) { frames = $0 }
    }
}

/// «Скрытые: + Fable + Память» — подписи-кнопки по левому краю под блоками; нажатие возвращает блок на его место.
private struct HiddenWidgetsRow: View {
    @ObservedObject var model: PanelModel
    let items: [PanelWidgetLayout.Item]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Скрытые").font(.system(size: 11)).foregroundColor(PanelColor.sub)
            ForEach(items) { item in
                Button { model.changeLayout { $0.setHidden(item.id, false) } } label: {
                    Text("+ " + (item.widget?.title ?? item.id)).font(.system(size: 11)).foregroundColor(PanelColor.text)
                }
                .buttonStyle(PressStyle())
                .handCursor()
                .help("Вернуть блок «\(item.widget?.title ?? item.id)»")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .transition(.opacity)
    }
}

private struct WidgetCell<Content: View>: View {
    @ObservedObject var model: PanelModel
    let item: PanelWidgetLayout.Item
    /// Один в ряду — стоит во всю ширину (WF187): «во всю ширину · половина» ему не нужны.
    let alone: Bool
    let frames: [String: CGRect]
    @ViewBuilder let content: () -> Content
    @Environment(\.pmpAccent) private var accent
    @State private var title: CGRect = .zero
    @State private var pending: DispatchWorkItem?
    @GestureState private var pressing = false

    private var dragging: Bool { model.widgetDrag?.id == item.id }
    private var lifted: Bool { dragging && model.widgetDrag?.cancelled == false }
    private var canToggle: Bool { !alone && (!item.wide || item.widget?.canNarrow == true) }
    private var shown: Bool { model.widgetChrome == item.id || dragging }

    var body: some View {
        content()
            .environment(\.panelNarrow, !item.wide && !alone)
            .environment(\.panelFill, true)
            .environment(\.widgetChromeShown, shown)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .coordinateSpace(name: widgetCellSpace)
            .onPreferenceChange(WidgetTitleKey.self) { title = $0 }
            .background(GeometryReader { proxy in
                Color.clear.preference(key: WidgetFramesKey.self,
                                       value: [item.id: proxy.frame(in: .named(widgetSpace))])
            })
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(accent.opacity(lifted ? 0.7 : 0), lineWidth: 1.5))
            .scaleEffect(lifted && !model.reduceMotion ? 1.02 : 1)
            .shadow(color: Color.black.opacity(lifted ? 0.45 : 0), radius: 12, y: 6)
            .animation(PanelSpring.press, value: lifted)
            // Значки — на месте заголовка, вровень с ним; заголовок под ними гаснет (`widgetTitle`): ничего не
            // сдвигается и не вылезает на соседний блок.
            .overlay(alignment: .topLeading) {
                if shown && title != .zero {
                    controls
                        .offset(x: title.minX - WidgetChrome.inset, y: title.midY - WidgetChrome.icon.height / 2)
                        .transition(.opacity)
                }
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let point):
                    hover(WidgetChrome.zone(title: title, icons: iconCount).contains(point))
                case .ended:
                    hover(false)
                }
            }
            .onDisappear { pending?.cancel() }
            .contextMenu {
                Button(item.wide ? "Половина — рядом с соседним" : "Во всю ширину") {
                    model.changeLayout { $0.toggleWidth(item.id) }
                }
                .disabled(!canToggle)
                Button("Скрыть блок") { model.changeLayout { $0.setHidden(item.id, true) } }
                Divider()
                Button("Вернуть как было") { model.changeLayout { $0 = .standard } }
                    .disabled(model.layout.isStandard)
            }
            .onChange(of: pressing) { down in if !down { model.endWidgetDrag() } }
    }

    private var iconCount: Int { canToggle ? 3 : 2 }

    /// Курсор над заголовком — значки через 0,8 с; ушёл — гаснут (WF187, #9247: «постоянно внимание на себя забирает»).
    private func hover(_ inside: Bool) {
        switch WidgetChrome.step(inside: inside, shown: model.widgetChrome == item.id, waiting: pending != nil) {
        case .wait:
            let work = DispatchWorkItem {
                pending = nil
                withAnimation(.easeInOut(duration: WidgetChrome.fade)) { model.widgetChrome = item.id }
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + WidgetChrome.delay, execute: work)
        case .cancel:
            pending?.cancel()
            pending = nil
        case .hide:
            pending?.cancel()
            pending = nil
            withAnimation(.easeInOut(duration: WidgetChrome.fade)) {
                if model.widgetChrome == item.id { model.widgetChrome = nil }
            }
        case .keep:
            break
        }
    }

    /// На месте заголовка: ручка (тащить), «во всю ширину ↔ половина» и крестик «скрыть» — тихие значки цветом
    /// подписей, без плашки (WF187; до того плашкой над углом блока — WF174, #9182 п. 5).
    private var controls: some View {
        HStack(spacing: WidgetChrome.spacing) {
            Image(systemName: "line.3.horizontal")
                .modifier(ChromeIcon(active: dragging))
                .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named(widgetSpace))
                    .updating($pressing) { _, state, _ in state = true }
                    .onChanged { value in
                        let hit = frames.first { $0.key != item.id && $0.value.contains(value.location) }?.key
                        model.dragWidget(item.id, over: hit)
                    }
                    .onEnded { _ in model.endWidgetDrag() })
                .onHover { inside in if inside { NSCursor.openHand.push() } else { NSCursor.pop() } }
                .help("Перетащи, чтобы переставить блок · Esc — отмена")
                .accessibilityLabel("Переставить блок «\(item.widget?.title ?? "")»")
            if canToggle {
                let help = item.wide ? "Половина — рядом с соседним блоком" : "Во всю ширину"
                Button { model.changeLayout { $0.toggleWidth(item.id) } } label: {
                    Image(systemName: item.wide ? "rectangle.split.2x1" : "rectangle").modifier(ChromeIcon())
                }
                .buttonStyle(PressStyle())
                .handCursor()
                .help(help)
                .accessibilityLabel(help)
            }
            Button { model.changeLayout { $0.setHidden(item.id, true) } } label: {
                Image(systemName: "xmark").modifier(ChromeIcon())
            }
            .buttonStyle(PressStyle())
            .handCursor()
            .help("Скрыть блок — вернуть: «Скрытые» под блоками")
            .accessibilityLabel("Скрыть блок «\(item.widget?.title ?? "")»")
        }
    }
}

/// Значок управления блоком: мелкий, цветом подписей, под курсором — цветом текста; без фона.
private struct ChromeIcon: ViewModifier {
    var active = false
    @State private var hover = false
    @Environment(\.pmpAccent) private var accent

    func body(content: Content) -> some View {
        content
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(active ? accent : hover ? PanelColor.text : PanelColor.sub)
            .frame(width: WidgetChrome.icon.width, height: WidgetChrome.icon.height)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
    }
}

// MARK: патч

private struct PatchCardView: View {
    @ObservedObject var model: PanelModel
    let card: PimpPanelText.PatchCard

    var body: some View {
        VStack(spacing: 8) {
            Text(card.title).font(.system(size: 13, weight: .semibold)).foregroundColor(PanelColor.text)
                .multilineTextAlignment(.center)
            Text(card.text).font(.system(size: 11)).foregroundColor(PanelColor.sub)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            switch model.patchRun {
            case .idle:
                BigButton(title: card.button) { notFound ? model.actions.findClaude() : model.actions.patch() }
                footnote
            case .running(let step):
                BigButton(title: step, enabled: false) {}
                footnote
            case .failed(let why):
                BigButton(title: "Ещё раз") { model.actions.patch() }
                Text(why).font(.system(size: 11)).foregroundColor(PanelColor.bad)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                LinkButton(title: "Подробнее…") { model.actions.patchLog() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private var notFound: Bool { model.patch == .claudeNotFound }

    @ViewBuilder private var footnote: some View {
        if notFound {
            LinkButton(title: card.footnote) { NSWorkspace.shared.open(URL(string: "https://claude.ai/download")!) }
        } else {
            Text(card.footnote).font(.system(size: 11)).foregroundColor(PanelColor.sub)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            // WF210 (#9382): заранее про окно связки ключей — оно придёт после патча.
            Text(PimpPanelText.keychainNote).font(.system(size: 11)).foregroundColor(PanelColor.sub)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: цвета (§2.3; с WF129 — #9040, #9020)

/// Квадрат цвета PMP (#9020 п. 7: «красивее, крупнее»): 31 pt; наведение — 1,08 пружиной, выбран — рамка цвета
/// текста через зазор 3 pt.
private struct ColorTile<Face: View>: View {
    static var size: CGFloat { 31 }
    var size: CGFloat = 31
    let selected: Bool
    let help: String
    let hover: (Bool) -> Void
    let action: () -> Void
    @ViewBuilder let face: () -> Face
    @State private var hovering = false

    var body: some View {
        let radius: CGFloat = size > Self.size ? 11 : 8
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Button(action: action) {
            face()
                .frame(width: size, height: size)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .overlay(RoundedRectangle(cornerRadius: radius + 2, style: .continuous)
                    .strokeBorder(PanelColor.text, lineWidth: selected ? 2 : 0).padding(-3))
                .scaleEffect(hovering ? 1.08 : 1)
                .animation(PanelSpring.press, value: hovering)
        }
        .buttonStyle(PressStyle())
        .onHover { inside in
            hovering = inside
            hover(inside)
        }
        .handCursor()
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// «Как у Claude» и цвет по проектам — образцы для свёрнутой строки.
private enum ColorSample {
    static let claude = PanelColor.hex(0xD97757)
}

/// «Свой цвет каждому проекту» (ставится из меню жёлтой кнопки): в свёрнутой строке — четыре цвета четвертями.
private struct ByProjectFace: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) { PanelColor.hex(0xB57BFF); PanelColor.hex(0x46D18B) }
            HStack(spacing: 0) { PanelColor.hex(0x5B9BFF); PanelColor.hex(0xFF9147) }
        }
    }
}

/// Оформление (#9040; WF141; WF169; WF174; WF177; WF180 — слово Элвиса 09.10 02:50: «Живые фоны все одинаковые»;
/// «Убери вот эту надпись "живой фон", переключалку. Все цвета тогда пусть будут как живой»; «не нужны мне большие
/// восемь штук, пусть маленькие чисто будут, сначала светлые, потом тёмные»; «Живой фон настройку сделай — включаем-
/// отключаем; она далеко, непонятно, что они связаны»). Свёрнут — строка «Оформление · образец · Живой ◯ ›».
/// Развёрнут: сразу под заголовком с переключателем «Живой» — полосы маленьких цветов (с WF210, слово 10.10:
/// тёмные, потом светлые, по цветовому кругу), ниже «Отсчёт» картинками. Выделен всегда цвет окон (`PanelColorTiles.picked`): «Живой» его не
/// меняет — включён, и живой фон идёт в тонах этого цвета (`PanelColorTiles.liveLook`), выключен — тот же цвет
/// статично. Имена — подсказкой при наведении; наведение на цвет — ещё и примерка в окне Claude.
private struct ColorsCard: View {
    @ObservedObject var model: PanelModel

    static let plainName = "Как у Claude"
    static let swatchHeight: CGFloat = 22
    /// Промежуток между плитками — один на все ряды блока, края рядов — по краям блока.
    static let gap: CGFloat = 4

    /// Цвета окон живут патчем: без него образцы приглушены и не нажимаются.
    private var patched: Bool {
        switch model.patch {
        case .installed, .unknown: return true
        default: return false
        }
    }

    private var spring: Animation { model.reduceMotion ? .easeOut(duration: 0.15) : PanelSpring.settings }

    private var picked: PanelColorTiles.Tile? { PanelColorTiles.picked(model.windowColor) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button(action: fold) {
                    HStack(spacing: 8) {
                        Text(PanelColorTiles.title).font(.system(size: 13, weight: .semibold))
                            .foregroundColor(PanelColor.text).widgetTitle()
                        if !model.colorsOpen {
                            current
                                .frame(width: 16, height: 16)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                        }
                        Spacer(minLength: 4)
                    }
                    .frame(minHeight: 18)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(scale: 0.99))
                .handCursor()
                .help(model.colorsOpen ? "Свернуть" : "Цвет окон Claude, живой фон и вид отсчёта")
                .accessibilityValue(model.colorsOpen ? "Открыто" : "Свёрнуто")
                liveToggle
                Button(action: fold) {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .foregroundColor(PanelColor.sub)
                        .rotationEffect(.degrees(model.colorsOpen ? 90 : 0))
                        .frame(width: 14, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .handCursor()
                .accessibilityHidden(true)
            }
            // WF210 (#9379 п. 2): беда патча — своей строкой под заголовком. В одной строке с «Живой ◯ ›» ей не хватало
            // места: заголовок ломался на «Оформлен-ие», сама строка резалась до «Цвета окон в…».
            if let trouble = trouble {
                Text(trouble).font(.system(size: 11)).foregroundColor(PanelColor.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.colorsOpen {
                VStack(alignment: .leading, spacing: 12) {
                    strips
                        .opacity(patched ? 1 : 0.4)
                        .disabled(!patched)
                        .onHover { inside in if !inside { model.actions.previewWindowColor(nil) } }
                    CountdownRow(model: model)
                }
                .transition(.opacity)
            }
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func fold() {
        withAnimation(spring) { model.colorsOpen.toggle() }
        PanelColorTiles.setOpen(model.colorsOpen)
    }

    /// «Живой ◯» — справа в заголовке, прямо над цветами: оживляет выбранный цвет, сам цвет не меняет.
    private var liveToggle: some View {
        let on = model.liveBackground
        return Button { model.actions.live(!on) } label: {
            HStack(spacing: 6) {
                Text(PanelColorTiles.liveTitle).font(.system(size: 11)).foregroundColor(PanelColor.sub)
                Switch(on: on)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .handCursor()
        .opacity(patched ? 1 : 0.4)
        .disabled(!patched)
        .help(on ? "Живой фон в тонах цвета — выключить" : "Живой фон в тонах выбранного цвета")
        .accessibilityLabel("Живой фон")
        .accessibilityValue(on ? "Включено" : "Выключено")
    }

    /// Образец выбранного в свёрнутой строке — неподвижный.
    @ViewBuilder private var current: some View {
        switch model.windowColor {
        case .plain: ColorSwatchFace(background: Self.claudeBackground, accent: ColorSample.claude)
        case .byProject: ByProjectFace()
        case .theme(let id):
            if let chip = model.allThemes.first(where: { $0.id == id }) {
                ColorSwatchFace(background: PanelColor.css(chip.background), accent: PanelColor.css(chip.accent))
            } else {
                ColorSample.claude
            }
        }
    }

    /// Строка под заголовком — только беда патча; имя выбранного — подсказкой образца (WF177: подписей-строк нет).
    private var trouble: String? {
        if case .lost = model.patch { return "Цвета окон вернутся вместе с патчем" }
        return patched ? nil : "Цвета окон — после патча"
    }

    /// Фон окна «как у Claude»: светлый или тёмный — как macOS сейчас.
    private static var claudeBackground: Color {
        NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? PanelColor.hex(0x262624) : PanelColor.hex(0xFAF9F5)
    }

    /// Полосы цветов: поровну образцов равной ширины, края в край; короткая последняя держит ту же ширину.
    private var strips: some View {
        let rows = PanelColorTiles.strips(model.windowThemes)
        let width = rows.map { $0.count }.max() ?? 0
        return VStack(alignment: .leading, spacing: Self.gap + 2) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, strip in
                HStack(spacing: Self.gap) {
                    ForEach(Array(strip.enumerated()), id: \.offset) { _, tile in swatch(tile) }
                    ForEach(0..<max(0, width - strip.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity).frame(height: Self.swatchHeight)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private func swatch(_ tile: PanelColorTiles.Tile) -> some View {
        let selected = picked == tile
        switch tile {
        case .plain:
            ColorSwatch(background: Self.claudeBackground, accent: ColorSample.claude, selected: selected,
                        help: Self.plainName, hover: { swatchHover(.plain, $0) },
                        action: { model.actions.windowColor(.plain) })
        case .theme(let id):
            if let chip = model.windowThemes.first(where: { $0.id == id }) {
                ColorSwatch(background: PanelColor.css(chip.background), accent: PanelColor.css(chip.accent),
                            selected: selected, help: chip.name, hover: { swatchHover(.theme(id), $0) },
                            action: { model.actions.windowColor(.theme(id)) })
            }
        }
    }

    /// Наведение на цвет — примерка в окне Claude в фокусе.
    private func swatchHover(_ choice: WindowColorChoice, _ inside: Bool) {
        if inside { model.actions.previewWindowColor(choice) }
    }
}

/// Лицо образца: фон темы и полоса акцента снизу — так выглядит окно, а не одна кнопка.
private struct ColorSwatchFace: View {
    let background: Color
    let accent: Color

    var body: some View {
        // WF180 («плитки заметно разные»): акцент — нижние две пятых, тёмные темы различаются им, а не фоном.
        GeometryReader { box in
            background.overlay(alignment: .bottom) { accent.frame(height: max(4, (box.size.height * 0.4).rounded())) }
        }
    }
}

/// Образец цвета (WF174): скруглённый прямоугольник — фон темы с полоской акцента; наведение — 1,08 пружиной,
/// выбран — рамка цвета текста через зазор 2 pt.
private struct ColorSwatch: View {
    let background: Color
    let accent: Color
    let selected: Bool
    let help: String
    let hover: (Bool) -> Void
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        Button(action: action) {
            ColorSwatchFace(background: background, accent: accent)
                .frame(maxWidth: .infinity)
                .frame(height: ColorsCard.swatchHeight)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(PanelColor.text, lineWidth: selected ? 1.5 : 0).padding(-2))
                .scaleEffect(hovering ? 1.08 : 1)
                .animation(PanelSpring.press, value: hovering)
        }
        .buttonStyle(PressStyle())
        .onHover { inside in
            hovering = inside
            hover(inside)
        }
        .handCursor()
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// «Отсчёт» (WF169, #9178; WF177, #9196: «должны быть прям картинки, как эти отсчёты выглядят»; WF180: «отсчёты должны
/// быть как плиточки слева направо», «это не взлёт, это ракета»): ряд из восьми картинок — кадр каждого вида К1 v3 на
/// кнопке «Отправить» (`CountdownFace`), выбранный в рамке, имя — подсказкой. Нажатие выбирает вид (команда
/// `send-look`; и у выбранного — повтором страницам). Строки про «Уменьшить движение» под рядом нет (WF181, #9217 п. 4):
/// выбор человека сильнее настройки macOS — страница играет выбранный вид и при ней.
private struct CountdownRow: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        let current = SendLook.isStyle(model.sendLookStyle) ? model.sendLookStyle : SendLook.defaultStyle
        VStack(alignment: .leading, spacing: 5) {
            Text(PanelColorTiles.countdownTitle).font(.system(size: 11)).foregroundColor(PanelColor.sub)
            HStack(spacing: ColorsCard.gap) {
                ForEach(SendLook.styles, id: \.id) { style in
                    CountdownTile(style: style.id, name: style.name, selected: style.id == current) {
                        model.actions.sendLookStyle(style.id)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Вид отсчёта: \(SendLook.name(current))")
    }
}

/// Плитка вида отсчёта: тёмное поле, на нём кнопка с кадром вида; наведение — 1,05 пружиной, выбран — рамка цвета
/// текста через зазор 2 pt, как у цветов.
private struct CountdownTile: View {
    let style: String
    let name: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Button(action: action) {
            CountdownFace(style: style)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(shape.fill(PanelColor.hex(0x2A2A2C)))
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.white.opacity(hovering ? 0.28 : 0.12), lineWidth: 1))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(PanelColor.text, lineWidth: selected ? 1.5 : 0).padding(-2))
                .scaleEffect(hovering ? 1.05 : 1)
                .animation(PanelSpring.press, value: hovering)
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
        .handCursor()
        .help("Отсчёт: " + name)
        .accessibilityLabel("Отсчёт: " + name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Узнаваемый кадр вида отсчёта на круглой кнопке «Отправить» (как рисует страница, раздел 12у): цвета — оранжевый
/// Claude на тёмном поле, янтарь шнура и пламени. Кадр неподвижный — середина отсчёта, цифра «3».
private struct CountdownFace: View {
    let style: String

    private static let accent = PanelColor.hex(0xD97757)
    private static let amber = PanelColor.hex(0xF59E0B)
    private static let field = PanelColor.hex(0x3A3A3C)
    private static let ink = PanelColor.hex(0xECECEE)
    private static let side: CGFloat = 20

    var body: some View {
        let accent = Self.accent, amber = Self.amber, ink = Self.ink, side = Self.side
        let tint = accent.opacity(0.32)
        ZStack {
            switch style {
            case "1.8": // Ракета: стрелка вверх, пламя под ней, метка секунд в углу.
                Circle().fill(tint)
                Capsule().fill(LinearGradient(colors: [PanelColor.hex(0xFFF6D0), amber, amber.opacity(0)],
                                              startPoint: .top, endPoint: .bottom))
                    .frame(width: 5, height: 10).offset(y: 9)
                Image(systemName: "arrow.up").font(.system(size: 10, weight: .bold)).foregroundColor(ink)
                Text("3").font(.system(size: 7, weight: .heavy)).foregroundColor(.white)
                    .frame(width: 10, height: 10).background(Circle().fill(accent)).offset(x: 9, y: -9)
            case "1.9": // Пульс: цифра дышит — крупная, с мягкой волной вокруг.
                Circle().strokeBorder(accent.opacity(0.35), lineWidth: 1.5).frame(width: side + 7, height: side + 7)
                Circle().fill(tint).frame(width: side, height: side)
                Text("3").font(.system(size: 13, weight: .heavy)).foregroundColor(accent)
            case "1.10": // Мерцание: ореол светится вокруг кнопки.
                Circle().stroke(accent.opacity(0.7), lineWidth: 3).blur(radius: 2.5).frame(width: side + 3, height: side + 3)
                Circle().fill(tint).frame(width: side, height: side)
                Text("3").font(.system(size: 11, weight: .semibold)).foregroundColor(ink)
            case "1.1": // Штрих по кругу: дуга растёт с головой-точкой.
                Circle().fill(Self.field)
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 2)
                Circle().trim(from: 0, to: 0.62).stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle().fill(Color.white).frame(width: 3, height: 3).offset(y: -side / 2)
                    .rotationEffect(.degrees(360 * 0.62))
                Text("3").font(.system(size: 10, weight: .bold)).foregroundColor(ink)
            case "1.2": // Удар: сплошной диск акцента и ударная волна.
                Circle().strokeBorder(accent.opacity(0.55), lineWidth: 1).frame(width: side + 8, height: side + 8)
                Circle().fill(accent).frame(width: side - 2, height: side - 2)
                Text("3").font(.system(size: 11, weight: .heavy)).foregroundColor(.white)
            case "1.4": // Кольцо: тонкое кольцо тает, цифра спокойная.
                Circle().fill(Self.field)
                Circle().stroke(ink.opacity(0.08), lineWidth: 1.5)
                Circle().trim(from: 0.38, to: 1).stroke(ink.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("3").font(.system(size: 10, weight: .semibold)).foregroundColor(ink)
            case "1.6": // Шнур: искра бежит по шнуру к кнопке с янтарной цифрой.
                Capsule().fill(amber.opacity(0.8)).frame(width: 6, height: 1.4).offset(x: -12.5)
                Circle().fill(PanelColor.hex(0xFFD27A)).frame(width: 3.5, height: 3.5).offset(x: -15.5)
                    .shadow(color: amber, radius: 2)
                Circle().fill(Self.field).frame(width: side, height: side)
                Circle().strokeBorder(amber.opacity(0.6), lineWidth: 1.2).frame(width: side, height: side)
                Text("3").font(.system(size: 10, weight: .bold)).foregroundColor(amber)
            default: // 1.5 Спокойная цифра: светлая кнопка, цифра цветом поля.
                Circle().fill(ink)
                Text("3").font(.system(size: 10, weight: .semibold)).foregroundColor(Self.field)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// Цвет PMP (#9020 п. 1–5): под шапкой по нажатию на значок; значок у часов и в шапке меняются вместе. С WF189
/// (слово Элвиса 09.10 04:00): цвета — одним рядом по всей ширине блока, по цветовому кругу, без подписи имени (имя —
/// подсказкой); ниже — варианты значка у часов той же сеткой («Как с цветами сделай — варианты»).
private struct AccentCard: View {
    @ObservedObject var model: PanelModel
    /// Девять цветов края в край по ширине блока (296 pt): 9 × 28 и восемь равных промежутков ≈ 5,5 pt.
    static let tile: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AccentTitle(title: "Цвет PMP", note: "значок у часов и эта панель")
            HStack(spacing: 0) {
                ForEach(Array(PMPAccent.allCases.enumerated()), id: \.element) { index, accent in
                    if index > 0 { Spacer(minLength: 2) }
                    ColorTile(size: Self.tile, selected: model.accent == accent, help: accent.name,
                              hover: { inside in
                                  if inside { model.accentPreview = accent }
                                  else if model.accentPreview == accent { model.accentPreview = nil }
                              },
                              action: { model.actions.setAccent(accent) }) {
                        PanelColor.hex(accent.hex)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            AccentTitle(title: "Значок", note: "в строке меню").padding(.top, 4)
            IconGroup(model: model)
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 10, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct AccentTitle: View {
    let title: String
    let note: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(PanelColor.text)
            Text(note).font(.system(size: 11)).foregroundColor(PanelColor.sub)
            Spacer(minLength: 0)
        }
    }
}

// MARK: лимиты

/// Полоска лимита: заливка — израсходованное (#7863, как у Claude), цвет — по остатку (8adc156).
private struct LimitBar: View {
    @Environment(\.pmpAccent) private var accent
    let fill: Int?
    let left: Int?
    let height: CGFloat

    private var color: Color {
        switch StatusIcon.level(left) {
        case .critical: return PanelColor.bad
        case .low: return PanelColor.warn
        case .normal: return accent
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                if let fill = fill, fill > 0 {
                    Capsule().fill(color).frame(width: max(height, proxy.size.width * CGFloat(fill) / 100))
                }
            }
        }
        .frame(height: height)
    }
}

/// Неделя — главным блоком (вернулся в #8958; значок с WF126 всегда про неделю, выбора главного лимита нет).
private struct MainLimit: View {
    @ObservedObject var model: PanelModel
    @Environment(\.panelNarrow) private var narrow

    var body: some View {
        let lim = StatusIcon.limit(.week, in: model.fresh)
        let left = StatusIcon.remaining(lim, now: model.now)
        let spent = StatusIcon.used(lim, now: model.now)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(narrow ? "НЕДЕЛЯ" : "НЕДЕЛЯ · ВСЕ МОДЕЛИ").font(.system(size: 10.5, weight: .semibold)).tracking(0.74)
                    .foregroundColor(PanelColor.sub).widgetTitle()
                Spacer()
                if !narrow, let reset = StatusIcon.resetText(lim?.resetsAt, now: model.now) {
                    Text(reset).font(.system(size: 11)).foregroundColor(PanelColor.sub)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                // Число — спокойным цветом текста, тревога — только цветом полоски (#8142, слово Элвиса 29.09:
                // «чересчур это ярко… 91% показывается прямо. Перебор»).
                Text(spent.map(String.init) ?? "—")
                    .font(.system(size: 34, weight: .medium, design: .monospaced))
                    .foregroundColor(left == nil ? PanelColor.sub : PanelColor.text.opacity(0.82))
                Text("%").font(.system(size: 19, weight: .semibold)).foregroundColor(PanelColor.sub)
                if !narrow {
                    Text("израсходовано").font(.system(size: 14)).foregroundColor(PanelColor.text).padding(.leading, 6)
                }
            }
            LimitBar(fill: spent, left: left, height: 8)
            if model.fresh == nil {
                Text("Лимиты придут, когда откроется окно Claude")
                    .font(.system(size: 11.5)).foregroundColor(PanelColor.sub)
            }
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 12, trailing: 12))
        .card(radius: 14)
    }
}

/// «5 часов» и «Fable» — два блока (WF174, #9182 п. 5), по умолчанию половинками в одном ряду.
private struct LimitTile: View {
    @ObservedObject var model: PanelModel
    let kind: StatusIcon.Mode

    var body: some View {
        let title = kind == .fable ? "FABLE" : "5 ЧАСОВ"
        let lim = StatusIcon.limit(kind, in: model.fresh)
        let left = StatusIcon.remaining(lim, now: model.now)
        let spent = StatusIcon.used(lim, now: model.now)
        return VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10.5, weight: .semibold)).tracking(0.74).foregroundColor(PanelColor.sub)
                .widgetTitle()
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(spent.map(String.init) ?? "—").font(.system(size: 24, weight: .medium, design: .monospaced))
                    .foregroundColor(left == nil ? PanelColor.sub : PanelColor.text.opacity(0.82))
                Text("%").font(.system(size: 13, weight: .semibold)).foregroundColor(PanelColor.sub)
            }
            LimitBar(fill: spent, left: left, height: 6)
            // У Fable строки сброса нет (#8895): он тот же, что у недели, и виден в полосе «Сброс»;
            // пустая строка держит высоту плиток равной.
            Text((kind == .fable ? nil : StatusIcon.resetText(lim?.resetsAt, now: model.now)) ?? " ")
                .font(.system(size: 11)).foregroundColor(PanelColor.sub).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: «Сброс»

/// Полоса недели (#8881, слово Элвиса 07.10: «в окне Пимпа не хватает… вот этого виджета»): «Сброс» и срок,
/// семь отрезков по дням лимитной недели, сегодняшний день подписан ярче. Заливка — спокойная, не акцент:
/// здесь показано, сколько недели прошло.
private struct WeekStripView: View {
    let strip: StatusIcon.WeekStrip
    @Environment(\.panelNarrow) private var narrow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Сброс").font(.system(size: 13)).foregroundColor(PanelColor.text).lineLimit(1)
                    .minimumScaleFactor(0.75).widgetTitle()
                Spacer(minLength: 4)
                // Срок — целиком, без «…» (WF187): ужимается подпись, а не число.
                Text(strip.left).font(.system(size: 13)).foregroundColor(PanelColor.sub).fixedSize()
            }
            HStack(spacing: 3) {
                ForEach(0..<strip.fills.count, id: \.self) { index in
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.10))
                            if strip.fills[index] > 0 {
                                Capsule().fill(PanelColor.text.opacity(0.62))
                                    .frame(width: max(5, proxy.size.width * CGFloat(strip.fills[index])))
                            }
                        }
                    }
                    .frame(height: 5)
                }
            }
            HStack(spacing: 3) {
                ForEach(0..<strip.days.count, id: \.self) { index in
                    Text(narrow ? String(strip.days[index].prefix(1)) : strip.days[index]).font(.system(size: 11, weight: index == strip.today ? .semibold : .regular))
                        .foregroundColor(index == strip.today ? PanelColor.text : PanelColor.sub.opacity(0.75))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12))
        .card()
    }
}

// MARK: «Идёт Workflow сейчас» (WF214, #9404)

/// Плитки-кольца по три в ряд (`docs/31.html`, 31.2): кольцо — доля готовых Workflow проекта, имя, «3 идут»; под ними
/// «Ждут тебя · N». Невесомо — без общей карточки, плитки стоят прямо на панели, края по краям соседних блоков.
/// Что именно идёт — подсказкой при наведении на плитку. Данные — `PanelTiles.groups`, те же, что у `/digest`.
private struct WorkflowNowView: View {
    @ObservedObject var model: PanelModel
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        let groups = model.projects.map { PanelTiles.groups($0, now: model.now) }
        let tiles = groups?.first { $0.group == .running }?.tiles ?? []
        let waiters = PanelTiles.waiters(groups ?? [])
        let count = PanelTiles.runningCount(groups ?? [])
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 6, height: 6)
                // Число — частью заголовка: под значками управления гаснет вместе с ним.
                HStack(spacing: 6) {
                    Text(PanelTiles.nowTitle).font(.system(size: 13, weight: .semibold)).foregroundColor(PanelColor.text)
                        .lineLimit(1)
                    if count > 0 {
                        Text("\(count)").font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(accent)
                    }
                }
                .widgetTitle()
                Spacer(minLength: 0)
            }
            .frame(minHeight: 18)
            if groups == nil {
                Text("Читаю проекты…").font(.system(size: 12)).foregroundColor(PanelColor.sub)
            } else if tiles.isEmpty {
                Text(PanelTiles.nowEmpty).font(.system(size: 12)).foregroundColor(PanelColor.sub)
            }
            let columns = PanelTiles.ringColumns
            ForEach(Array(stride(from: 0, to: tiles.count, by: columns)), id: \.self) { start in
                let row = tiles[start..<min(start + columns, tiles.count)]
                HStack(alignment: .top, spacing: 6) {
                    ForEach(row) { tile in RingTile(tile: tile) }
                    ForEach(0..<(columns - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if !waiters.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ждут тебя · \(waiters.count)").textCase(.uppercase)
                        .font(.system(size: 10.5, weight: .semibold)).tracking(0.74).foregroundColor(PanelColor.sub)
                    ForEach(waiters.prefix(PanelTiles.waitersLimit)) { tile in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Circle().fill(PanelColor.warn).frame(width: 6, height: 6)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 2 }
                            (Text(tile.name).fontWeight(.semibold).foregroundColor(PanelColor.text)
                                + Text(tile.wait.isEmpty ? "" : " — " + tile.wait).foregroundColor(PanelColor.sub))
                                .font(.system(size: 11)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        }
                        .help(tile.wait.isEmpty ? tile.name : tile.name + " — " + tile.wait)
                    }
                    if waiters.count > PanelTiles.waitersLimit {
                        Text("и " + waiters.dropFirst(PanelTiles.waitersLimit).map { $0.name }.joined(separator: ", "))
                            .font(.system(size: 11)).foregroundColor(PanelColor.sub)
                            .fixedSize(horizontal: false, vertical: true).padding(.leading, 12)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Плитка-кольцо проекта: кольцо «готово из всех» и маркер, имя, «3 идут»; точка в углу — ждёт (жёлтая) или упал
/// (красная). Наведение — что идёт и на каком шаге.
private struct RingTile: View {
    let tile: PanelTile
    @Environment(\.pmpAccent) private var accent
    @State private var hover = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let ring = PanelTiles.ring(tile)
        let words = PanelTiles.ringWords(tile)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 6) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 4)
                    Circle().trim(from: 0, to: ring.fraction)
                        .stroke(PanelColor.good, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(ring.text)
                        .font(.system(size: ring.text.count > 4 ? 8 : ring.text.count > 3 ? 9 : 10, weight: .semibold,
                                      design: .monospaced))
                        .foregroundColor(PanelColor.text).lineLimit(1).fixedSize()
                }
                .frame(width: 30, height: 30)
                .padding(4)
                Text(tile.marker).font(.system(size: 12))
                Spacer(minLength: 0)
            }
            Text(tile.name).font(.system(size: 11.5, weight: .semibold)).foregroundColor(PanelColor.text)
                .lineLimit(1).minimumScaleFactor(0.75).frame(height: 15).padding(.top, 6)
            Text(words.text).font(.system(size: 11)).foregroundColor(words.failed ? PanelColor.bad : PanelColor.sub)
                .lineLimit(1).padding(.top, 2)
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 7, leading: 6, bottom: 7, trailing: 6))
        .frame(maxWidth: .infinity, minHeight: 96, maxHeight: .infinity, alignment: .topLeading)
        .background(shape.fill(Color.white.opacity(hover ? 0.08 : 0.045)))
        .overlay(shape.strokeBorder(hover ? accent.opacity(0.45) : PanelColor.frame, lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            if let corner = PanelTiles.corner(tile) {
                Circle().fill(corner == .failed ? PanelColor.bad : PanelColor.warn).frame(width: 8, height: 8).padding(7)
            }
        }
        .contentShape(shape)
        .onHover { hover = $0 }
        .help(([tile.marker + " " + tile.name] + (tile.help.isEmpty ? [] : [tile.help])
               + (tile.terminal ? ["Есть чат в терминале"] : [])).joined(separator: "\n"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile.name), \(words.text)")
    }
}

// MARK: «Температура»

/// Температура Мака (#8898, `docs/25.html` раздел 4): свёрнуто — строка «Температура · линия за 3 ч · 54°»,
/// нажал — график за 3 часа, наведи — градусы на тот момент. Чип, без него — батарея (`MacTemperature`).
private struct TemperatureView: View {
    @ObservedObject var model: PanelModel
    @State private var hover = false
    @Environment(\.panelNarrow) private var narrow

    var body: some View {
        let history = model.temperature
        let last = history.last
        let now = last?.value.map(MacTemperature.degrees) ?? "—"
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(model.reduceMotion ? .easeOut(duration: 0.15) : PanelSpring.settings) {
                    model.temperatureOpen.toggle()
                }
            } label: {
                // В половинке — зазоры уже: «Температура» помещается своим кеглем, как «Память» рядом (WF181).
                HStack(spacing: narrow ? 5 : 8) {
                    Text("Температура").font(.system(size: 13)).foregroundColor(PanelColor.text).lineLimit(1)
                        .minimumScaleFactor(0.75).widgetTitle()
                    Spacer(minLength: narrow ? 2 : 6)
                    if model.temperatureOpen {
                        // В половинке — только градусы: с «чип » заголовок резался до «Температ…» (WF214); откуда
                        // градусы, сказано подписью под графиком.
                        Text((narrow ? "" : last?.isChip == true ? "чип " : "батарея ") + now)
                            .font(.system(size: 13)).monospacedDigit().foregroundColor(PanelColor.text).fixedSize()
                    } else {
                        if !narrow { TemperatureSpark(history: history).frame(width: 56, height: 16) }
                        Text(now).font(.system(size: 13)).monospacedDigit().foregroundColor(PanelColor.text).fixedSize()
                    }
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .foregroundColor(PanelColor.sub)
                        .rotationEffect(.degrees(model.temperatureOpen ? 90 : 0))
                }
                .frame(minHeight: 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.99))
            .onHover { hover = $0 }
            .handCursor()
            .accessibilityLabel("Температура")
            .accessibilityValue(now)
            if model.temperatureOpen {
                TemperatureChart(history: history).frame(height: 132)
                    .transition(.opacity)
                let caption = MacTemperature.caption(history)
                if !caption.isEmpty {
                    Text(caption).font(.system(size: 11)).foregroundColor(PanelColor.sub)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
        }
        .padding(EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12))
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(hover ? 0.03 : 0)))
        .card()
    }
}

// MARK: «Нагрузка на память»

/// Нагрузка на память (#9082, WF164, `docs/31.html` 31.5; WF177 — #9197) — как температура: свёрнуто — «Нагрузка на
/// память · линия за 3 ч · 6,3 ГБ», линия цветом уровня macOS; нажал — график за 3 ч по оси «0 · 4 · 8 ГБ» (вся память
/// Мака) с заливкой по уровням, наведи — «20:07 · 6,3 ГБ · под нагрузкой». Число одно — в строке; подпись — слово
/// уровня его цветом и «за 3 ч от A до B ГБ».
private struct MemoryView: View {
    @ObservedObject var model: PanelModel
    @State private var hover = false
    @Environment(\.panelNarrow) private var narrow

    var body: some View {
        let history = model.memory
        let now = MacMemory.nowText(history)
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(model.reduceMotion ? .easeOut(duration: 0.15) : PanelSpring.settings) {
                    model.memoryOpen.toggle()
                }
            } label: {
                HStack(spacing: narrow ? 5 : 8) {
                    Text(narrow ? "Память" : "Нагрузка на память").font(.system(size: 13)).foregroundColor(PanelColor.text)
                        .lineLimit(1).minimumScaleFactor(0.75).widgetTitle()
                    Spacer(minLength: narrow ? 2 : 6)
                    if !model.memoryOpen && !narrow { MemorySpark(history: history).frame(width: 56, height: 16) }
                    Text(now).font(.system(size: 13)).monospacedDigit().foregroundColor(PanelColor.text).fixedSize()
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .foregroundColor(PanelColor.sub)
                        .rotationEffect(.degrees(model.memoryOpen ? 90 : 0))
                }
                .frame(minHeight: 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.99))
            .onHover { hover = $0 }
            .handCursor()
            .help(MacMemory.help(history))
            .accessibilityLabel("Нагрузка на память")
            .accessibilityValue(MacMemory.help(history))
            if model.memoryOpen {
                MemoryChart(history: history).frame(height: 132)
                    .transition(.opacity)
                let caption = MacMemory.captionParts(history)
                if !caption.word.isEmpty || !caption.rest.isEmpty {
                    (Text(caption.word).foregroundColor(memoryColor(history.last?.level))
                        + Text(caption.word.isEmpty || caption.rest.isEmpty ? "" : " · ")
                        + Text(caption.rest).foregroundColor(PanelColor.sub))
                        .font(.system(size: 11))
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
        }
        .padding(EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12))
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(hover ? 0.03 : 0)))
        .card()
    }
}

/// Цвет уровня, как в «Мониторинге системы»; не знаем — зелёный.
private func memoryColor(_ level: MemoryPressureLevel?) -> Color {
    switch level ?? .normal {
    case .normal: return PanelColor.good
    case .warn: return PanelColor.warn
    case .critical: return PanelColor.bad
    }
}

private func memoryX(_ history: [MacMemorySample], _ index: Int, from x0: CGFloat, to x1: CGFloat) -> CGFloat {
    chartX(history[index].at, first: history.first?.at, last: history.last?.at, from: x0, to: x1)
}

/// Линия за 3 ч в свёрнутой строке: занятое (доля всей памяти), свой масштаб по мин–макс, куски цветом уровня,
/// разрывы — где Мак спал.
private struct MemorySpark: View {
    let history: [MacMemorySample]

    var body: some View {
        Canvas { context, size in
            let values = history.map { (MacMemory.fraction($0) ?? 0) * 100 }
            guard let low = values.min(), let high = values.max() else { return }
            let range = max(high - low, 10)
            let mid = (high + low) / 2
            func point(_ index: Int) -> CGPoint {
                CGPoint(x: memoryX(history, index, from: 1, to: size.width - 1),
                        y: size.height - 1.5 - CGFloat((values[index] - (mid - range / 2)) / range) * (size.height - 3))
            }
            for band in MacMemory.bands(history) {
                var path = Path()
                path.move(to: point(band.indices[0]))
                if band.indices.count == 1 {
                    let dot = point(band.indices[0])
                    path.addEllipse(in: CGRect(x: dot.x - 1, y: dot.y - 1, width: 2, height: 2))
                } else {
                    for index in band.indices.dropFirst() { path.addLine(to: point(index)) }
                }
                context.stroke(path, with: .color(memoryColor(band.level)),
                               style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

/// График за 3 ч (31.5; WF177 — #9197): шкала «0 · 4 · 8 ГБ» от всей памяти Мака, высота — занятое, часы внизу,
/// «сейчас» справа; под линией заливка цветом уровня; наведение — крест, точка и «20:07 · 6,3 ГБ · под нагрузкой».
private struct MemoryChart: View {
    let history: [MacMemorySample]
    @State private var hovered: Int?
    @Environment(\.pmpAccent) private var accent

    private static let left: CGFloat = 40
    private static let right: CGFloat = 8
    private static let top: CGFloat = 10
    private static let bottom: CGFloat = 104

    var body: some View {
        GeometryReader { proxy in
            let x1 = proxy.size.width - Self.right
            let y: (Double) -> CGFloat = { fraction in Self.bottom - CGFloat(fraction) * (Self.bottom - Self.top) }
            let point: (Int) -> CGPoint = { index in
                CGPoint(x: memoryX(history, index, from: Self.left, to: x1), y: y(MacMemory.fraction(history[index]) ?? 0))
            }
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    let mono = Font.system(size: 10, design: .monospaced)
                    for tick in MacMemory.axis(total: history.last?.total ?? 0) {
                        var line = Path()
                        line.move(to: CGPoint(x: Self.left, y: y(tick.fraction)))
                        line.addLine(to: CGPoint(x: x1, y: y(tick.fraction)))
                        context.stroke(line, with: .color(PanelColor.frame), lineWidth: 1)
                        context.draw(Text(tick.label).font(mono).foregroundColor(PanelColor.sub),
                                     at: CGPoint(x: Self.left - 6, y: y(tick.fraction)), anchor: .trailing)
                    }
                    for label in chartHourLabels(first: history.first?.at, last: history.last?.at, left: Self.left, x1: x1) {
                        context.draw(Text(label.text).font(mono).foregroundColor(PanelColor.sub),
                                     at: CGPoint(x: label.x, y: 120), anchor: label.anchor)
                    }
                    for band in MacMemory.bands(history) where band.indices.count > 1 {
                        let color = memoryColor(band.level)
                        var line = Path()
                        line.move(to: point(band.indices[0]))
                        for index in band.indices.dropFirst() { line.addLine(to: point(index)) }
                        var fill = line
                        fill.addLine(to: CGPoint(x: point(band.indices[band.indices.count - 1]).x, y: Self.bottom))
                        fill.addLine(to: CGPoint(x: point(band.indices[0]).x, y: Self.bottom))
                        fill.closeSubpath()
                        context.fill(fill, with: .color(color.opacity(0.28)))
                        context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                    if let last = history.indices.last {
                        let dot = point(last)
                        context.fill(Path(ellipseIn: CGRect(x: dot.x - 3.5, y: dot.y - 3.5, width: 7, height: 7)),
                                     with: .color(memoryColor(history[last].level)))
                    }
                    if let index = hovered, history.indices.contains(index) {
                        let dot = point(index)
                        var cross = Path()
                        cross.move(to: CGPoint(x: dot.x, y: Self.top))
                        cross.addLine(to: CGPoint(x: dot.x, y: Self.bottom))
                        context.stroke(cross, with: .color(PanelColor.text.opacity(0.35)), lineWidth: 1)
                        context.fill(Path(ellipseIn: CGRect(x: dot.x - 4, y: dot.y - 4, width: 8, height: 8)),
                                     with: .color(accent))
                        context.stroke(Path(ellipseIn: CGRect(x: dot.x - 4, y: dot.y - 4, width: 8, height: 8)),
                                       with: .color(PanelColor.panel), lineWidth: 2)
                    }
                }
                if let index = hovered, history.indices.contains(index), let value = MacMemory.amount(history[index]) {
                    let x = point(index).x
                    let level = history[index].level.map { " · " + MacMemory.word($0) } ?? ""
                    Text("\(chartClock.string(from: history[index].at)) · \(value)\(level)")
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(PanelColor.text)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(PanelColor.hex(0x2E2E31)))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(PanelColor.frame, lineWidth: 1))
                        .fixedSize()
                        .position(x: x1 - Self.left < 200 ? (Self.left + x1) / 2 : min(max(x, Self.left + 100), x1 - 100), y: 9)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let fraction = Double((location.x - Self.left) / max(1, x1 - Self.left))
                    hovered = (-0.02...1.02).contains(fraction) ? MacMemory.nearest(history, fraction: fraction) : nil
                case .ended:
                    hovered = nil
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Нагрузка на память за 3 часа")
        .accessibilityValue(MacMemory.caption(history))
    }
}

// MARK: «Токены»

/// Слова плитки «Токены» (WF187, #9250, слово Элвиса 09.10 03:35: «там же просто можно „944 млн“ написать, а у тебя
/// многоточие… что этот маленький график значит?»): подпись под линией и подсказка по наведению.
enum TokensTileText {
    static let sparkCaption = "7 дней"
    static let sparkHelp = "Токены по дням за 7 дней, справа — сегодня"

    static func help(_ spark: TokenSpark?, collected: String) -> String {
        let tail = collected.isEmpty ? "" : " · " + collected
        if spark?.isEmpty != false { return "За 7 дней токенов нет: копилку Rick/data/tokens-daily.json пополняет Рик" + tail }
        if spark?.today == nil { return "Сегодня Рик ещё не собирал токены" + tail }
        return sparkHelp + tail
    }
}

/// Плитка «Токены» (WF157, #9149; WF170, #9179): «Токены · линия общего расхода за 7 дней · сегодня N»; нажал —
/// окно с графиком рядом. День, который Рик ещё не собрал, — «—», а не «0». WF187 (#9250): число всегда целиком
/// («944 млн», «1,2 млрд») — ужимается подпись «Токены», а не число; под линией мелко «7 дней», сегодня — точкой.
private struct TokensTile: View {
    @ObservedObject var model: PanelModel
    @State private var hover = false
    @Environment(\.panelNarrow) private var narrow

    var body: some View {
        let spark = model.tokenSpark
        let today = spark?.todayText ?? "—"
        let collected = TokenStats.scannedText(spark?.scanned, now: Date())
        Button { model.openTokens() } label: {
            HStack(spacing: narrow ? 5 : 8) {
                Text("Токены").font(.system(size: 13)).foregroundColor(PanelColor.text).lineLimit(1)
                    .minimumScaleFactor(0.75).widgetTitle()
                Spacer(minLength: narrow ? 2 : 6)
                if !narrow && spark?.isEmpty == false {
                    VStack(spacing: 0) {
                        TokensSpark(values: spark?.values ?? []).frame(width: 56, height: 16)
                        Text(TokensTileText.sparkCaption).font(.system(size: 9)).foregroundColor(PanelColor.sub)
                            .fixedSize()
                    }
                    .help(TokensTileText.sparkHelp)
                }
                // WF177: «нет данных» и «не собрано» — словами и тихо, число — ярко.
                (Text(narrow || spark?.isEmpty != false ? "" : "сегодня ").foregroundColor(PanelColor.sub)
                    + Text(today).foregroundColor(spark?.today == nil || spark?.isEmpty != false ? PanelColor.sub : PanelColor.text))
                    .font(.system(size: 13)).monospacedDigit().fixedSize()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    .foregroundColor(PanelColor.sub)
            }
            .frame(minHeight: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.99))
        .onHover { hover = $0 }
        .handCursor()
        .help(TokensTileText.help(spark, collected: collected))
        .accessibilityLabel("Токены")
        .accessibilityValue("сегодня " + today)
        .padding(EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12))
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(hover ? 0.03 : 0)))
        .card()
    }
}

/// Плавная линия общего расхода за 7 дней с заливкой цветом PMP, сегодня — точкой справа; шкала от нуля по
/// максимуму недели. Несобранный день (nil) не рисуется — линия кончается на последнем собранном.
private struct TokensSpark: View {
    let values: [Int?]

    var body: some View {
        Canvas { context, size in
            guard values.count > 1, let top = values.compactMap({ $0 }).max(), top > 0 else { return }
            let accent = PanelColor.hex(PMPAccent.current.hex)
            // Поля 4 pt со всех сторон — ореол сегодняшней точки не обрезается.
            let step = (size.width - 8) / CGFloat(values.count - 1)
            let points = values.enumerated().compactMap { index, value in
                value.map { CGPoint(x: 4 + CGFloat(index) * step,
                                    y: size.height - 4 - CGFloat($0) / CGFloat(top) * (size.height - 8)) }
            }
            guard let first = points.first, let last = points.last else { return }
            var line = Path()
            line.move(to: first)
            for index in points.indices.dropFirst() {
                let from = points[index - 1], to = points[index]
                let middle = (from.x + to.x) / 2
                line.addCurve(to: to, control1: CGPoint(x: middle, y: from.y), control2: CGPoint(x: middle, y: to.y))
            }
            var area = line
            area.addLine(to: CGPoint(x: last.x, y: size.height))
            area.addLine(to: CGPoint(x: first.x, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .linearGradient(Gradient(colors: [accent.opacity(0.35), accent.opacity(0)]),
                                                     startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(line, with: .color(accent), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            // Сегодня — выделенной точкой с ореолом (WF187): справа — сегодняшний день.
            if values.last ?? nil != nil {
                context.fill(Path(ellipseIn: CGRect(x: last.x - 4, y: last.y - 4, width: 8, height: 8)),
                             with: .color(accent.opacity(0.28)))
                context.fill(Path(ellipseIn: CGRect(x: last.x - 2.5, y: last.y - 2.5, width: 5, height: 5)), with: .color(accent))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Ось X по времени: первая точка — левый край, последняя — правый; одна точка — справа.
private func temperatureX(_ history: [MacTemperatureSample], _ index: Int, from x0: CGFloat, to x1: CGFloat) -> CGFloat {
    chartX(history[index].at, first: history.first?.at, last: history.last?.at, from: x0, to: x1)
}

private func chartX(_ at: Date, first: Date?, last: Date?, from x0: CGFloat, to x1: CGFloat) -> CGFloat {
    guard let first = first, let last = last else { return x1 }
    let span = last.timeIntervalSince(first)
    guard span > 0 else { return x1 }
    return x0 + CGFloat(at.timeIntervalSince(first) / span) * (x1 - x0)
}

/// Линия за 3 часа в свёрнутой строке: свой масштаб по мин–макс, разрывы — где Мак спал.
private struct TemperatureSpark: View {
    let history: [MacTemperatureSample]

    var body: some View {
        Canvas { context, size in
            let values = history.map { $0.value ?? 0 }
            guard let low = values.min(), let high = values.max() else { return }
            let range = max(high - low, 4)
            let mid = (high + low) / 2
            func point(_ index: Int) -> CGPoint {
                CGPoint(x: temperatureX(history, index, from: 1, to: size.width - 1),
                        y: size.height - 1.5 - CGFloat((values[index] - (mid - range / 2)) / range) * (size.height - 3))
            }
            for segment in MacTemperature.segments(history) {
                var path = Path()
                path.move(to: point(segment[0]))
                if segment.count == 1 {
                    path.addEllipse(in: CGRect(x: point(segment[0]).x - 1, y: point(segment[0]).y - 1, width: 2, height: 2))
                } else {
                    for index in segment.dropFirst() { path.addLine(to: point(index)) }
                }
                context.stroke(path, with: .color(PanelColor.text.opacity(0.7)),
                               style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

/// График за 3 часа (кадр 4.2): шкала по 20°, часы внизу, «сейчас» справа; наведение — крест, точка и «00:40 · 61°».
private struct TemperatureChart: View {
    let history: [MacTemperatureSample]
    @State private var hovered: Int?
    @Environment(\.pmpAccent) private var accent

    private static let left: CGFloat = 30
    private static let right: CGFloat = 8
    private static let top: CGFloat = 10
    private static let bottom: CGFloat = 104

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        GeometryReader { proxy in
            let x1 = proxy.size.width - Self.right
            let scale = MacTemperature.scale(history)
            let y: (Double) -> CGFloat = { value in
                Self.bottom - CGFloat((value - scale.low) / (scale.high - scale.low)) * (Self.bottom - Self.top)
            }
            let point: (Int) -> CGPoint = { index in
                CGPoint(x: temperatureX(history, index, from: Self.left, to: x1), y: y(history[index].value ?? scale.low))
            }
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    let mono = Font.system(size: 10, design: .monospaced)
                    for tick in scale.ticks {
                        var line = Path()
                        line.move(to: CGPoint(x: Self.left, y: y(tick)))
                        line.addLine(to: CGPoint(x: x1, y: y(tick)))
                        context.stroke(line, with: .color(PanelColor.frame), lineWidth: 1)
                        context.draw(Text(MacTemperature.degrees(tick)).font(mono).foregroundColor(PanelColor.sub),
                                     at: CGPoint(x: Self.left - 6, y: y(tick)), anchor: .trailing)
                    }
                    for label in hourLabels(x1: x1) {
                        context.draw(Text(label.text).font(mono).foregroundColor(PanelColor.sub),
                                     at: CGPoint(x: label.x, y: 120), anchor: label.anchor)
                    }
                    for segment in MacTemperature.segments(history) where segment.count > 1 {
                        var path = Path()
                        path.move(to: point(segment[0]))
                        for index in segment.dropFirst() { path.addLine(to: point(index)) }
                        context.stroke(path, with: .color(PanelColor.text),
                                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                    if let last = history.indices.last {
                        let dot = point(last)
                        context.fill(Path(ellipseIn: CGRect(x: dot.x - 3.5, y: dot.y - 3.5, width: 7, height: 7)),
                                     with: .color(PanelColor.text))
                    }
                    if let index = hovered, history.indices.contains(index) {
                        let dot = point(index)
                        var cross = Path()
                        cross.move(to: CGPoint(x: dot.x, y: Self.top))
                        cross.addLine(to: CGPoint(x: dot.x, y: Self.bottom))
                        context.stroke(cross, with: .color(PanelColor.text.opacity(0.35)), lineWidth: 1)
                        context.fill(Path(ellipseIn: CGRect(x: dot.x - 4, y: dot.y - 4, width: 8, height: 8)),
                                     with: .color(accent))
                        context.stroke(Path(ellipseIn: CGRect(x: dot.x - 4, y: dot.y - 4, width: 8, height: 8)),
                                       with: .color(PanelColor.panel), lineWidth: 2)
                    }
                }
                if let index = hovered, history.indices.contains(index), let value = history[index].value {
                    let x = point(index).x
                    Text("\(Self.clock.string(from: history[index].at)) · \(MacTemperature.degrees(value))")
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(PanelColor.text)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(PanelColor.hex(0x2E2E31)))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(PanelColor.frame, lineWidth: 1))
                        .fixedSize()
                        .position(x: min(max(x, Self.left + 36), x1 - 36), y: 9)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let fraction = Double((location.x - Self.left) / max(1, x1 - Self.left))
                    hovered = (-0.02...1.02).contains(fraction) ? MacTemperature.nearest(history, fraction: fraction) : nil
                case .ended:
                    hovered = nil
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Температура за 3 часа")
        .accessibilityValue(MacTemperature.caption(history))
    }

    private func hourLabels(x1: CGFloat) -> [(text: String, x: CGFloat, anchor: UnitPoint)] {
        chartHourLabels(first: history.first?.at, last: history.last?.at, left: Self.left, x1: x1)
    }
}

private let chartClock: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
}()

/// Подписи часов графиков за 3 ч (температура, память): первая точка, дальше каждый час от неё, справа — «сейчас».
private func chartHourLabels(first: Date?, last: Date?, left: CGFloat, x1: CGFloat) -> [(text: String, x: CGFloat, anchor: UnitPoint)] {
    guard let first = first, let last = last else { return [] }
    let span = last.timeIntervalSince(first)
    var labels: [(text: String, x: CGFloat, anchor: UnitPoint)] = [("сейчас", x1, .trailing)]
    guard span >= 20 * 60 else { return labels }
    labels.append((chartClock.string(from: first), left, .leading))
    var hour: TimeInterval = 3600
    while hour < span - 30 * 60 {
        labels.append((chartClock.string(from: first.addingTimeInterval(hour)),
                       left + CGFloat(hour / span) * (x1 - left), .center))
        hour += 3600
    }
    return labels
}

// MARK: выключатели

private struct Switch: View {
    let on: Bool
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule().fill(on ? accent : Color.white.opacity(0.16))
            Circle().fill(Color.white).frame(width: 13, height: 13).padding(2)
        }
        .frame(width: 28, height: 17)
        .animation(PanelSpring.press, value: on)
    }
}

// MARK: настройки (§7)

/// Сводки и строки листа «Настройки» — что сейчас выбрано, одной строкой справа у группы.
enum SettingsText {
    /// Группа «Окна и Mac» — все выключатели, кроме двух из «Дополнительно».
    static func windowToggles(_ toggles: [PanelToggle]) -> [PanelToggle] {
        toggles.filter { $0.id != AutomationDefaults.allowKey && $0.id != AutomationDefaults.continueKey }
    }

    /// «3 с» / «нет» — сводка группы «Задержка» (WF180: «не "отправка", а "задержка"»).
    static func enter(_ delay: SendDelaySetting) -> String { delay.on ? "\(delay.seconds) с" : "нет" }

    /// «Bypass» или пусто; строки «ответ в …» с WF129 нет — ответов из панели больше нет (#9023).
    static func chats(bypass: Bool) -> String { bypass ? "Bypass" : "" }

    static func pinned(_ look: PinnedLook) -> String {
        switch (look.folder, look.clock) {
        case (true, true): return "проект и таймер"
        case (true, false): return "только проект"
        case (false, true): return "только таймер"
        case (false, false): return "ничего"
        }
    }

    static func windows(_ toggles: [PanelToggle]) -> String {
        let list = windowToggles(toggles)
        if list.contains(where: { $0.needsAccess }) { return "нужен доступ" }
        let on = list.filter { $0.on }.count
        return on == list.count ? "всё включено" : "включено \(on) из \(list.count)"
    }

    static func claudeVersion(_ patch: StatusIcon.Patch) -> String? {
        switch patch {
        case .installed(let version, _), .notInstalled(let version), .lost(let version, _): return version
        case .claudeNotFound, .unknown: return nil
        }
    }

    /// Строка Claude в «Обновлениях»: что с обновлением сейчас; `ready` — есть что ставить («Обновить»).
    static func update(_ block: PimpPanelText.UpdateBlock) -> (text: String, ready: Bool) {
        switch block {
        case .none: return ("обновлений нет", false)
        case .available(let version, _, _): return ("вышла \(version)", false)
        case .downloading: return ("качаю обновление", false)
        case .verifying(let version, _): return ("проверяю \(version)", false)
        case .ready(let version, _), .timely(let version, _): return ("скачалась \(version)", true)
        case .snoozed: return ("обновление отложено", true)
        case .installing(let version, _): return ("ставлю \(version)", false)
        case .done(let version): return ("поставлена \(version)", false)
        case .failed(let why): return (why, false)
        }
    }

    static func updates(_ block: PimpPanelText.UpdateBlock, patch: StatusIcon.Patch) -> String {
        if block == .none { return claudeVersion(patch).map { "Claude \($0)" } ?? "" }
        return update(block).text
    }

    /// «по ширине · поля 32» — выбор блока «Текст» (WF167).
    static func text(justify: Bool, padding: Int) -> String { (justify ? "по ширине" : "влево") + " · поля \(padding)" }

    static func more(autoAllow: Bool) -> String { autoAllow ? "Allow — сам" : "" }

    /// Строка под переключателем Bypass: текст и вид (нет ссылки — `link == false`).
    static func permission(_ value: BypassNew.Permission) -> (text: String, good: Bool, warn: Bool, link: Bool) {
        switch value {
        case .allowed: return ("✓ Режим разрешён в Claude", true, false, false)
        case .notAllowed: return ("Сначала разреши режим в настройках Claude", false, true, true)
        case .blockedByOrg: return ("Bypass выключен организацией", false, true, false)
        case .unknown: return ("Проверю, когда Claude запустится", false, false, false)
        }
    }
}

/// Лист «Настройки» за шестерёнкой (WF126 §7): группы-карточки, открыта всегда одна, справа — что выбрано.
struct SettingsSheet: View {
    @ObservedObject var model: PanelModel
    @Environment(\.pmpAccent) private var accent

    var autoAllowToggle: PanelToggle? {
        model.toggles.first { $0.id == AutomationDefaults.allowKey }
    }

    var autoAllowBinding: Binding<Bool> {
        Binding(get: { autoAllowToggle?.on ?? false }, set: { on in
            guard let toggle = autoAllowToggle, toggle.on != on else { return }
            model.actions.toggle(toggle.id)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(model.reduceMotion ? .easeOut(duration: 0.15) : PanelSpring.settings) {
                    model.settingsGroup = nil
                    model.sheet = .panel
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        .foregroundColor(PanelColor.sub)
                    Text("Настройки").font(.system(size: 13, weight: .semibold)).foregroundColor(PanelColor.text)
                    Spacer()
                }
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.99))
            .handCursor()
            .help("Назад (Esc)")
            SettingsGroupCard(model: model, group: .text, title: "Текст",
                              summary: SettingsText.text(justify: model.textJustify, padding: model.sidePadding)) {
                TextGroup(model: model)
            }
            SettingsGroupCard(model: model, group: .enter, title: "Задержка",
                              summary: SettingsText.enter(model.sendDelay)) { EnterGroup(model: model) }
            SettingsGroupCard(model: model, group: .chats, title: "Чаты",
                              summary: SettingsText.chats(bypass: model.bypassNew)) { ChatsGroup(model: model) }
            SettingsGroupCard(model: model, group: .pinned, title: "Закреплённые чаты",
                              summary: SettingsText.pinned(model.pinnedLook)) { PinnedGroup(model: model) }
            SettingsGroupCard(model: model, group: .windows, title: "Окна и Mac",
                              summary: SettingsText.windows(model.toggles)) { windowsGroup }
            SettingsGroupCard(model: model, group: .updates, title: "Обновления",
                              summary: SettingsText.updates(model.update, patch: model.patch)) { updatesGroup }
            SettingsGroupCard(model: model, group: .more, title: "Дополнительно",
                              summary: SettingsText.more(autoAllow: autoAllowToggle?.on ?? false)) { moreGroup }
            footer.padding(.top, 2)
        }
    }

    // MARK: группы без своего состояния

    private var windowsGroup: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsText.windowToggles(model.toggles)) { toggle in
                SettingsSwitchRow(title: toggle.title, on: toggle.on, needsAccess: toggle.needsAccess,
                                  help: toggle.toolTip) { model.actions.toggle(toggle.id) }
            }
            SettingsActionRow(title: "Разрешения macOS…", chevron: true) { model.actions.setup() }
        }
    }

    private var updatesGroup: some View {
        let update = SettingsText.update(model.update)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Claude \(SettingsText.claudeVersion(model.patch) ?? "—")").font(.system(size: 13))
                        .foregroundColor(PanelColor.text)
                    Text(update.text).font(.system(size: 11)).foregroundColor(PanelColor.sub).lineLimit(2)
                }
                Spacer(minLength: 6)
                if update.ready { SmallButton(title: "Обновить") { Self.pressUpdate(model) } }
            }
            .frame(minHeight: 36)
            SettingsSwitchRow(title: "Обновлять Пимп и Viewer самим", on: model.selfUpdate.on,
                              help: "Новая версия скачивается заранее, проверяется по подписи автора и встаёт при запуске Claude или Пимпа",
                              caption: model.selfUpdate.line.isEmpty ? nil : model.selfUpdate.line) {
                model.actions.selfUpdate(!model.selfUpdate.on)
            }
            SettingsActionRow(title: "Снять патч…", color: PanelColor.danger) { model.actions.uninstall() }
        }
    }

    /// «Обновить» в группе: сперва лист «Панель» — там карточка обновления со всеми состояниями
    /// (вопрос «идут чаты — обновить всё равно?» рисуется только там), потом само обновление.
    static func pressUpdate(_ model: PanelModel) {
        withAnimation(model.reduceMotion ? .easeOut(duration: 0.15) : PanelSpring.settings) {
            model.settingsGroup = nil
            model.sheet = .panel
        }
        model.actions.update()
    }

    private var moreGroup: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let toggle = autoAllowToggle {
                SettingsSwitchRow(title: "Сам нажимать «Allow once»", on: toggle.on, help: toggle.toolTip,
                                  caption: "Кроме удаления, выкладки, денег и паролей. Сильнее — Bypass permissions в «Чатах».") {
                    autoAllowBinding.wrappedValue = !toggle.on
                }
            }
            if let toggle = model.toggles.first(where: { $0.id == AutomationDefaults.continueKey }) {
                SettingsSwitchRow(title: "Новый чат по блоку передачи", on: toggle.on, mixed: toggle.mixed,
                                  help: toggle.toolTip, caption: "Сам открывает новый чат, когда ты не печатаешь.") {
                    model.actions.toggle(toggle.id)
                }
            }
            TeamPullsSection(pulls: model.teamPulls)
            rickRow
            SettingsActionRow(title: model.archiving ? "Сохраняю чаты…" : "Сохранить все чаты в архив",
                              color: model.archiving ? PanelColor.sub : PanelColor.text) {
                guard !model.archiving else { return }
                model.actions.archiveChats()
            }
            .disabled(model.archiving)
            .help("Все чаты Claude Code одним zip с оглавлением — на склад «_Не удалять/Склад чатов Claude»")
            SettingsActionRow(title: "Открыть PimpViewer") { model.actions.showViewer() }
                .help("Все HTML и фото всех чатов одной лентой")
            // Виджеты панели (WF129, #9043): порядок и ширина блоков — как было.
            SettingsActionRow(title: model.layout.isStandard ? "Блоки панели — как было" : "Блоки панели — вернуть как было",
                              color: model.layout.isStandard ? PanelColor.sub : PanelColor.text) {
                model.changeLayout { $0 = .standard }
            }
            .disabled(model.layout.isStandard)
            .help("Порядок и ширина блоков меняются ручкой в углу блока и правым кликом")
            if model.donateAvailable {
                // Одна тихая строка без цифр (WF227, кадр 37.9): счёт и способы оплаты живут только в окне.
                SettingsActionRow(title: "Поддержать автора") { model.actions.donate() }
                    .help("Окно «Поддержать автора»: кто делает Пимп и как сказать спасибо")
                SettingsSwitchRow(title: "Показывать «Поддержать» в меню окна", on: model.donateShown,
                                  help: "Выключено — нет пункта в меню жёлтой кнопки") { model.actions.toggleDonate() }
            }
        }
    }

    /// Рик — житель Пимпа (WF216): у тех, кто ставил Пимп раньше, — тихая строка, пока папки Rick нет.
    @ViewBuilder private var rickRow: some View {
        switch model.rick {
        case .hidden: EmptyView()
        case .done(let path):
            // Путь — своей строкой под кнопкой, как подпись у «Поставить Рика»: рядом с кнопкой он не помещается.
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text("Рик стоит").font(.system(size: 13)).foregroundColor(PanelColor.text)
                    Spacer(minLength: 6)
                    SmallButton(title: "Показать в Finder", primary: false) { model.actions.revealRick() }
                }
                .frame(minHeight: 28)
                Text(path).font(.system(size: 11)).foregroundColor(PanelColor.sub)
                    .lineLimit(1).truncationMode(.middle)
                    .padding(.bottom, 4)
            }
        case .idle, .running, .failed:
            let running = model.rick == .running
            VStack(alignment: .leading, spacing: 0) {
                SettingsActionRow(title: running ? "Ставлю Рика…" : "Поставить Рика",
                                  color: running ? PanelColor.sub : PanelColor.text) {
                    guard !running else { return }
                    model.actions.installRick()
                }
                .disabled(running)
                Text(model.rick.caption).font(.system(size: 11))
                    .foregroundColor(model.rick.isFailed ? PanelColor.warn : PanelColor.sub)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)
            }
        }
    }

    /// «О программе» · «Выйти ⌘Q» — подписи-ссылки одной строкой (§7.7; «Снять патч…» — в «Обновлениях»).
    private var footer: some View {
        HStack(spacing: 6) {
            FooterLink(title: "О программе") { model.actions.about() }
            Text("·").font(.system(size: 11)).foregroundColor(PanelColor.sub)
            FooterLink(title: "Выйти ⌘Q") { model.actions.quit() }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }
}

/// Карточка группы: заголовок 36 pt (имя · сводка · шеврон), под ним — содержимое, когда открыта.
private struct SettingsGroupCard<Content: View>: View {
    @ObservedObject var model: PanelModel
    let group: SettingsGroup
    let title: String
    let summary: String
    @ViewBuilder let content: () -> Content
    @State private var hover = false

    var body: some View {
        let open = model.settingsGroup == group
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(model.reduceMotion ? .easeOut(duration: 0.15) : PanelSpring.settings) {
                    model.settingsGroup = open ? nil : group
                }
            } label: {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(PanelColor.text)
                        .lineLimit(1).layoutPriority(1)
                    Spacer(minLength: 6)
                    Text(summary).font(.system(size: 11))
                        .foregroundColor(summary == "нужен доступ" ? PanelColor.warn : PanelColor.sub).lineLimit(1)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .foregroundColor(PanelColor.sub)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(Color.white.opacity(hover ? 0.06 : 0))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.99))
            .onHover { hover = $0 }
            .handCursor()
            .accessibilityLabel(title)
            .accessibilityValue(open ? "Открыто" : "Свёрнуто")
            if open {
                content()
                    .padding(EdgeInsets(top: 2, leading: 10, bottom: 10, trailing: 10))
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .card()
    }
}

/// Строка-переключатель группы: подпись 13, справа — `Switch` (или «нужен доступ» / «сохранённые»), под ней — подпись 11.
private struct SettingsSwitchRow: View {
    let title: String
    let on: Bool
    var needsAccess = false
    var mixed = false
    var help = ""
    var caption: String?
    let action: () -> Void
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 13)).foregroundColor(PanelColor.text).lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 6)
                    if needsAccess {
                        Text("нужен доступ").font(.system(size: 11, weight: .semibold)).foregroundColor(PanelColor.warn)
                    } else if mixed {
                        Text("сохранённые").font(.system(size: 11)).foregroundColor(PanelColor.sub)
                    } else {
                        Switch(on: on)
                    }
                }
                .frame(minHeight: 28)
                if let caption = caption {
                    Text(caption).font(.system(size: 11)).foregroundColor(PanelColor.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, caption == nil ? 0 : 4)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(hover ? 0.06 : 0)))
            .padding(.horizontal, -6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.99))
        .onHover { hover = $0 }
        .animation(reduceMotion ? nil : PanelSpring.press, value: hover)
        .handCursor()
        .help(help)
        .accessibilityLabel(title)
        .accessibilityValue(needsAccess ? "нужен доступ" : (on ? "Включено" : "Выключено"))
    }
}

/// Строка-кнопка группы: наведение — фон светлее.
private struct SettingsActionRow: View {
    let title: String
    var color: Color = PanelColor.text
    var chevron = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 13)).foregroundColor(color)
                Spacer(minLength: 6)
                if chevron {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .foregroundColor(PanelColor.sub)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(hover ? 0.06 : 0)))
            .padding(.horizontal, -6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.99))
        .onHover { hover = $0 }
        .handCursor()
    }
}

/// Сегменты 24 pt: выбранный — заливка акцентом.
private struct Segments<Value: Hashable>: View {
    let items: [(value: Value, title: String)]
    let selected: Value
    let pick: (Value) -> Void
    @Environment(\.pmpAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: Int?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                let chosen = item.value == selected
                Button { if !chosen { pick(item.value) } } label: {
                    Text(item.title).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundColor(chosen ? PanelColor.ink : PanelColor.text)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(chosen ? accent : Color.white.opacity(hovered == index ? 0.14 : 0.08)))
                }
                .buttonStyle(PressStyle())
                .onHover { inside in
                    if inside { hovered = index } else if hovered == index { hovered = nil }
                }
                .animation(reduceMotion ? nil : PanelSpring.press, value: hovered)
                .handCursor()
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
    }
}

/// Подпись над сегментами: имя 13 и пояснение 11.
private func settingsLabel(_ title: String, _ hint: String? = nil) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(title).font(.system(size: 13)).foregroundColor(PanelColor.text)
        if let hint = hint { Text(hint).font(.system(size: 11)).foregroundColor(PanelColor.sub) }
        Spacer(minLength: 0)
    }
    .padding(.top, 6)
}

private struct FooterLink: View {
    let title: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 11)).foregroundColor(hover ? PanelColor.text : PanelColor.sub)
                .underline(hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .handCursor()
    }
}

// MARK: «Задержка» (§7.2; WF180)

/// «Задержка» (WF180, слово Элвиса 09.10 02:50: «Отправка по Enter 3 секунды; "второй Enter" — не второй, а Enter, пока
/// идёт отсчёт; Shift+Enter убери вообще; "Сделать баннер на завтра" — убери… не "отправка", а "задержка"»): сегменты
/// задержки, Enter во время отсчёта — выключатель «отменить», Esc — отмена всегда, звук, показ в окне. Строки — тем же
/// видом, что остальные группы: подпись слева, значение справа; без эмодзи.
private struct EnterGroup: View {
    @ObservedObject var model: PanelModel
    static let delayItems: [(value: Int, title: String)] = [(0, "нет"), (3, "3 с"), (5, "5 с"), (10, "10 с")]

    var body: some View {
        let delay = model.sendDelay
        let keys = model.enterKeys
        VStack(alignment: .leading, spacing: 2) {
            Segments(items: Self.delayItems,
                     selected: delay.on ? delay.seconds : 0) { seconds in
                model.actions.sendDelay(seconds != 0, seconds == 0 ? delay.seconds : seconds)
            }
            .padding(.top, 2)
            .padding(.bottom, 4)
            if delay.on {
                SettingsSwitchRow(title: "Enter во время отсчёта — отменить", on: keys.second == .cancel,
                                  help: "Выключено — Enter во время отсчёта отправляет сразу") {
                    model.actions.enterKeys(EnterKeys(second: keys.second == .cancel ? .send : .cancel, shift: keys.shift))
                }
                HStack {
                    Text("Esc — отмена").font(.system(size: 13)).foregroundColor(PanelColor.text)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 28)
                HStack {
                    Text("⇧Enter, ⌘Enter, ⌥Enter — перенос строки").font(.system(size: 13)).foregroundColor(PanelColor.text)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 28)
                CountdownSoundMenu(selected: model.countdownSound) { model.actions.countdownSound($0) }
                SettingsActionRow(title: "Показать в окне Claude", chevron: true) {
                    model.actions.previewSendDelay(delay.seconds)
                }
                .help("Показать отсчёт в окне Claude, ничего не отправляя")
            }
            if let line = model.sendDelayLine {
                Text(line).font(.system(size: 11)).foregroundColor(PanelColor.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// «Звук» (WF151, #9108; WF180 — без эмодзи): строка «Звук · выбранный», по нажатию — список из пяти, галка у текущего.
private struct CountdownSoundMenu: View {
    let selected: CountdownSound
    let pick: (CountdownSound) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("Звук").font(.system(size: 13)).foregroundColor(PanelColor.text)
            Spacer(minLength: 6)
            Menu {
                ForEach(CountdownSound.allCases, id: \.self) { sound in
                    Button { if sound != selected { pick(sound) } } label: {
                        if sound == selected { Label(sound.name, systemImage: "checkmark") } else { Text(sound.name) }
                    }
                }
            } label: {
                Text(selected.name).font(.system(size: 11)).foregroundColor(PanelColor.sub)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .handCursor()
        }
        .frame(minHeight: 28)
        .accessibilityLabel("Звук отсчёта: \(selected.name)")
    }
}

// MARK: «Значок» (WF180, WF189)

/// «Значок» (WF180; WF189 — под «Цвет PMP», слово Элвиса 09.10 04:00: «варианты отображения в строке меню, как
/// раньше… иконками чик-чик-чик, можно было выбрать. Как с цветами сделай»): картинки вариантов (`StatusIcon.Variant`)
/// сеткой по четыре на полосе цвета строки меню, последний ряд — двумя широкими (по две колонки); выбранный в рамке,
/// имя — подсказкой.
private struct IconGroup: View {
    @ObservedObject var model: PanelModel
    static let columns = 4
    static let spacing: CGFloat = 6

    var body: some View {
        let variants = StatusIcon.Variant.allCases
        VStack(spacing: Self.spacing) {
            ForEach(Array(stride(from: 0, to: variants.count, by: Self.columns)), id: \.self) { start in
                HStack(spacing: Self.spacing) {
                    ForEach(variants[start..<min(start + Self.columns, variants.count)], id: \.self) { variant in
                        IconTile(image: IconSample.image(variant, accent: model.shownAccent.nsColor, projects: summary),
                                 name: variant.name, selected: model.iconVariant == variant) {
                            if model.iconVariant != variant { model.actions.iconVariant(variant) }
                        }
                    }
                }
            }
        }
    }

    /// Сводка проектов на образце: настоящая, если проекты уже читали.
    private var summary: String {
        guard let snapshot = model.projects else { return IconSample.projects }
        let text = PanelTiles.summary(PanelTiles.groups(snapshot, now: model.now))
        return text.isEmpty ? IconSample.projects : text
    }
}

/// Образцы вариантов значка: та же кисть, что у строки меню (`StatusIconArt`), на тёмной полосе.
enum IconSample {
    static let projects = "⏳ 2 · WF 3/8"

    static func look(_ variant: StatusIcon.Variant, projects: String = projects, now: Date = Date()) -> StatusIcon.Look {
        let limits = ClaudeLimits(at: now, plan: nil, fiveHour: .init(used: 24, resetsAt: nil),
                                  weekly: .init(used: 37, resetsAt: nil), fable: .init(used: 8, resetsAt: nil),
                                  source: "api")
        let base = StatusIcon.look(mode: variant.mode, limits: limits, patch: .unknown, phase: .idle, now: now)
        return StatusIcon.compose(base, variant: variant, summary: projects, toolTip: "")
    }

    static func image(_ variant: StatusIcon.Variant, accent: NSColor, projects: String = projects) -> NSImage {
        StatusIconArt.image(look(variant, projects: projects), dark: true, accent: accent)
    }
}

/// Плитка варианта значка — тем же видом, что плитка цвета (`ColorTile`): высота 28, скругление 8, рамка
/// выбранного 2 pt снаружи.
private struct IconTile: View {
    let image: NSImage
    let name: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button(action: action) {
            // WF210 (#9379 п. 2): картинка шире плитки ужимается, а не распирает блок — настоящая сводка проектов
            // («⏳ 3 · ✋ 5 · WF 127/133») на двух широких плитках не помещалась в ряд и сдвигала всю панель влево.
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: image.size.width, maxHeight: image.size.height)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
                .frame(height: AccentCard.tile)
                .background(shape.fill(PanelColor.hex(0x1C1C1E)))
                .overlay(shape.strokeBorder(Color.white.opacity(hovering ? 0.30 : 0.18), lineWidth: 1))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(PanelColor.text, lineWidth: selected ? 2 : 0).padding(-3))
                .scaleEffect(hovering ? 1.04 : 1)
                .animation(PanelSpring.press, value: hovering)
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
        .handCursor()
        .help(name)
        .accessibilityLabel("Значок: " + name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: «Чаты» (§7.3)

private struct ChatsGroup: View {
    @ObservedObject var model: PanelModel
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        let line = SettingsText.permission(model.bypassPermission)
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text("+").font(.system(size: 15)).foregroundColor(PanelColor.sub)
                    chip(model.bypassNew ? "BY" : "AU", lit: model.bypassNew)
                    chip("O55", lit: false)
                    chip("HI", lit: false)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(PanelColor.hex(0x2B2440)))
                Text("так начнётся новый чат из PMP").font(.system(size: 11)).foregroundColor(PanelColor.sub)
            }
            .accessibilityElement(children: .combine)
            SettingsSwitchRow(title: BypassNew.menuTitle, on: model.bypassNew,
                              caption: "Claude не спрашивает разрешений: сам правит файлы и запускает команды. Включай только для своих проектов. PMP ставит Bypass в каждом открытом чате и в новых; чат, где ты сам выбрал режим, не трогает. Claude один раз на проект спросит подтверждение — подтверди сам.") {
                model.actions.bypassNew(!model.bypassNew)
            }
            .padding(.top, 4)
            Text(line.text).font(.system(size: 11, weight: line.good || line.warn ? .semibold : .regular))
                .foregroundColor(line.good ? PanelColor.good : (line.warn ? PanelColor.warn : PanelColor.sub))
            if line.link {
                LinkButton(title: model.claudeSettingsFailed ? "Claude → Settings…" : "Открыть настройки Claude") {
                    model.actions.openClaudeSettings()
                }
                .handCursor()
            }
        }
    }

    private func chip(_ text: String, lit: Bool) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundColor(lit ? accent : PanelColor.sub)
            .padding(.horizontal, 5).frame(height: 18)
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(lit ? accent : Color.clear, lineWidth: 1))
    }
}

// MARK: «Закреплённые чаты» (§7.4)

private struct PinnedGroup: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        let look = model.pinnedLook
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Pinned").font(.system(size: 11)).foregroundColor(PanelColor.sub)
                row(look, clock: "42:10", hot: false, project: "VkusnoffKz", title: "Корзина и варианты…")
                row(look, clock: "6:05", hot: true, project: "Rick", title: "Рик чат для Элвиса")
                row(look, clock: "0:00", hot: true, project: "PimpMyClaude", title: "Ночь 07.10")
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(PanelColor.hex(0x2A1640)))
            .animation(model.reduceMotion ? nil : PanelSpring.press, value: look)
            .accessibilityElement(children: .combine)
            Text("так выглядит список слева").font(.system(size: 11)).foregroundColor(PanelColor.sub)
            SettingsSwitchRow(title: "Название проекта", on: look.folder,
                              caption: "плашка с папкой перед названием чата") {
                model.actions.pinnedLook(PinnedLook(folder: !look.folder, clock: look.clock))
            }
            .padding(.top, 4)
            SettingsSwitchRow(title: "Таймер кеша", on: look.clock,
                              caption: "час с последнего ответа; меньше 10 минут — красный") {
                model.actions.pinnedLook(PinnedLook(folder: look.folder, clock: !look.clock))
            }
        }
    }

    private func row(_ look: PinnedLook, clock: String, hot: Bool, project: String, title: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(PanelColor.sub).frame(width: 4, height: 4)
            if look.clock {
                Text(clock).font(.system(size: 11, design: .monospaced))
                    .foregroundColor(hot ? PanelColor.bad : PanelColor.sub)
                    .transition(.opacity)
            }
            if look.folder {
                Text(project).font(.system(size: 11)).foregroundColor(PanelColor.text)
                    .padding(.horizontal, 5).frame(height: 16)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white.opacity(0.10)))
                    .transition(.opacity)
            }
            Text(title).font(.system(size: 13)).foregroundColor(PanelColor.text).lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

// MARK: «Текст» (WF167, #9168)

/// Выравнивание ответов и поля по бокам — для всех окон сразу; быстрый ползунок «↔️ Поля» на «−» остаётся.
private struct TextGroup: View {
    @ObservedObject var model: PanelModel
    static let alignItems: [(value: Bool, title: String)] = [(false, "Влево"), (true, "По ширине")]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextPreview(justify: model.textJustify, padding: model.sidePadding)
                .animation(model.reduceMotion ? nil : PanelSpring.press, value: model.textJustify)
                .animation(model.reduceMotion ? nil : PanelSpring.press, value: model.sidePadding)
            Text("так ляжет ответ в окне Claude").font(.system(size: 11)).foregroundColor(PanelColor.sub)
            settingsLabel("Выравнивание")
            Segments(items: Self.alignItems, selected: model.textJustify) { model.actions.textJustify($0) }
            settingsLabel("Поля", "по бокам, px")
            PaddingSlider(value: model.sidePadding) { model.actions.sidePadding($0) }
            // WF210 (#9398, К-CA): служебные строки под ответом — расход и состояние; «Работа идёт» остаётся.
            SettingsSwitchRow(title: CleanAnswers.title, on: model.cleanAnswers, caption: CleanAnswers.caption) {
                model.actions.cleanAnswers(!model.cleanAnswers)
            }
            .padding(.top, 4)
        }
    }
}

/// Превью колонки ответа: абзац полосками; по ширине — строки до правого края, кроме последней; поля — отступ
/// с обеих сторон (половина пикселей окна — превью в половину ширины колонки).
private struct TextPreview: View {
    let justify: Bool
    let padding: Int
    static let ragged: [CGFloat] = [0.94, 0.82, 0.97, 0.88, 0.55]

    var body: some View {
        GeometryReader { geo in
            let inset = 6 + CGFloat(padding) / 2
            let width = max(0, geo.size.width - inset * 2)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Self.ragged.indices, id: \.self) { index in
                    let last = index == Self.ragged.count - 1
                    Capsule().fill(PanelColor.text.opacity(0.55))
                        .frame(width: width * (justify && !last ? 1 : Self.ragged[index]), height: 4)
                }
            }
            .padding(.horizontal, inset)
            .padding(.vertical, 10)
        }
        .frame(height: 64)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(PanelColor.hex(0x262624)))
        .accessibilityElement()
        .accessibilityLabel("Так ляжет ответ: \(justify ? "по ширине" : "влево"), поля \(padding)")
    }
}

/// «Поля» 0…40: дорожка с отметками 24/32/40 (нажатие на число — встать на отметку), значение справа.
/// Тянуть и щёлкать по дорожке — живо, каждый шаг сразу в claude.json (лоадер подхватит за ~1 с).
private struct PaddingSlider: View {
    let value: Int
    let change: (Int) -> Void
    @Environment(\.pmpAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false
    @State private var dragging = false
    private let range = TextLook.paddingRange
    private let knob: CGFloat = 14

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            GeometryReader { geo in
                let track = max(1, geo.size.width - knob)
                VStack(spacing: 2) {
                    ZStack(alignment: .topLeading) {
                        let fill = x(value, track) - knob / 2
                        Capsule().fill(Color.white.opacity(0.14)).frame(width: track, height: 4)
                            .position(x: knob / 2 + track / 2, y: 9)
                        Capsule().fill(accent).frame(width: fill, height: 4)
                            .position(x: knob / 2 + fill / 2, y: 9)
                        ForEach(TextLook.paddingMarks, id: \.self) { mark in
                            Circle().fill(mark <= value ? PanelColor.ink.opacity(0.5) : PanelColor.sub)
                                .frame(width: 3, height: 3)
                                .position(x: x(mark, track), y: 9)
                        }
                        Circle().fill(Color.white)
                            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
                            .frame(width: knob, height: knob)
                            .scaleEffect(hover || dragging ? 1.15 : 1)
                            .position(x: x(value, track), y: 9)
                    }
                    .frame(width: geo.size.width, height: 18)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            dragging = true
                            let next = step(at: drag.location.x, track)
                            if next != value { change(next) }
                        }
                        .onEnded { _ in dragging = false })
                    .onHover { hover = $0 }
                    ZStack(alignment: .topLeading) {
                        ForEach(TextLook.paddingMarks, id: \.self) { mark in
                            Text("\(mark)").font(.system(size: 10)).monospacedDigit()
                                .foregroundColor(mark == value ? PanelColor.text : PanelColor.sub)
                                .fixedSize()
                                .frame(width: 26, height: 14)
                                .contentShape(Rectangle())
                                .onTapGesture { if mark != value { change(mark) } }
                                .handCursor()
                                .position(x: x(mark, track), y: 7)
                        }
                    }
                    .frame(width: geo.size.width, height: 14, alignment: .topLeading)
                }
            }
            .frame(height: 34)
            .animation(reduceMotion ? nil : PanelSpring.press, value: hover || dragging)
            Text("\(value)").font(.system(size: 13)).monospacedDigit().foregroundColor(PanelColor.text)
                .frame(width: 22, height: 18, alignment: .trailing)
        }
        .handCursor()
        .accessibilityElement()
        .accessibilityLabel("Поля по бокам")
        .accessibilityValue("\(value) px")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if value < range.upperBound { change(value + 1) }
            case .decrement: if value > range.lowerBound { change(value - 1) }
            @unknown default: break
            }
        }
    }

    /// Центр бегунка для значения: от knob/2 до ширины − knob/2.
    private func x(_ value: Int, _ track: CGFloat) -> CGFloat {
        let span = CGFloat(range.upperBound - range.lowerBound)
        return knob / 2 + track * CGFloat(min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / span
    }

    private func step(at location: CGFloat, _ track: CGFloat) -> Int {
        let span = Double(range.upperBound - range.lowerBound)
        let raw = Double((location - knob / 2) / track) * span + Double(range.lowerBound)
        return min(max(Int(raw.rounded()), range.lowerBound), range.upperBound)
    }
}

// MARK: обновление Claude

private struct UpdateBlockView: View {
    @ObservedObject var model: PanelModel
    @Environment(\.pmpAccent) private var accent
    @State private var breathe = false

    var body: some View {
        // Дышит только в открытой панели: закрытая — ни анимаций, ни нагрузки (z6-r08).
        let timely: Bool = {
            if case .timely = model.update { return model.phase == .open }
            return false
        }()
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(EdgeInsets(top: 10, leading: 12, bottom: 12, trailing: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(PanelColor.panel))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(timely && breathe ? accent : PanelColor.frame, lineWidth: 1))
            .onAppear { startBreathing(timely) }
            .onChange(of: timely) { startBreathing($0) }
    }

    private func startBreathing(_ on: Bool) {
        // Выключение — своей короткой анимацией: иначе повторяющаяся может остаться крутиться.
        guard on, !model.reduceMotion else { withAnimation(.linear(duration: 0)) { breathe = false }; return }
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { breathe = true }
    }

    private func title(_ text: String) -> some View {
        Text(text).font(.system(size: 13, weight: .semibold)).foregroundColor(PanelColor.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func sub(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundColor(PanelColor.sub).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var content: some View {
        switch model.update {
        case .none:
            EmptyView()
        case .available(let version, _, _) where model.refusedVersion == version:
            title("PMP пока не патчит Claude \(version)")
            sub("Стоящий Claude не тронут. Новая версия PMP научится — предложу снова.")
        case .available(let version, let canWrite, let note):
            title("Вышел Claude \(version)")
            if let note = note { sub(note) }
            if canWrite {
                SmallButton(title: "Скачать") { model.actions.download() }
            } else {
                sub("Нет прав на папку «Программы» — поставь сам с claude.ai/download")
                LinkButton(title: "claude.ai/download") {
                    NSWorkspace.shared.open(URL(string: "https://claude.ai/download")!)
                }
            }
        case .downloading(let race):
            RaceView(model: model, race: race, startedAt: model.raceStartedAt, memory: model.lanes,
                     title: "Качаю Claude \(race.version)",
                     note: "подпись Anthropic проверю в конце — откуда бы ни скачалось") { model.actions.cancelRace() }
        case .verifying(_, let from):
            title("Проверяю подпись Anthropic…")
            sub((from.map { "файл с \($0)" } ?? "файл скачан") + ", проверка — как у официального")
        case .ready(let version, let question):
            title("Скачалось обновление")
            sub("Claude \(version) · подпись Anthropic ✓" + (model.readySize.map { " · \($0)" } ?? ""))
            if let question = question {
                Text(question).font(.system(size: 13, weight: .semibold)).foregroundColor(PanelColor.warn)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    SmallButton(title: "Обновить всё равно") { model.actions.updateAnyway() }
                    SmallButton(title: "Подождать", primary: false) { model.actions.wait() }
                }
            } else {
                BigButton(title: "Обновить Claude") { model.actions.update() }
                sub("Claude закроется секунд на 20 — окна вернутся на места")
            }
            // WF210 (#9382): заранее про окно связки ключей — оно придёт после обновления и патча.
            sub(PimpPanelText.keychainNote)
        case .timely(let version, let reason):
            title("Самое время обновиться")
            Text(reason).font(.system(size: 11, weight: .semibold)).foregroundColor(PanelColor.good)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(PanelColor.good.opacity(0.14)))
            sub("Claude \(version) скачан и проверен")
            HStack(spacing: 8) {
                SmallButton(title: "Обновить сейчас") { model.actions.updateNow() }
                SmallButton(title: "Позже", primary: false) { model.actions.later() }
            }
            sub(PimpPanelText.keychainNote)
        case .snoozed:
            sub("Хорошо, напомню через 3 часа")
        case .installing(let version, let step):
            HStack {
                title("Обновляю Claude до \(version)")
                Spacer()
                Text("\(min(step + 1, 5))/5").font(.system(size: 11, design: .monospaced)).foregroundColor(PanelColor.sub)
            }
            sub("Claude закрыт секунд на 20 — дальше всё само")
            ForEach(Array(PimpPanelText.installSteps(version: version, loader: model.loader).enumerated()),
                    id: \.offset) { index, text in
                HStack(spacing: 8) {
                    StepDot(state: index < step ? .done : (index == step ? .running : .waiting))
                    Text(text).font(.system(size: 13))
                        .foregroundColor(index <= step ? PanelColor.text : PanelColor.sub)
                }
            }
        case .done(let version):
            Text("✓ Claude \(version) стоит, патч на месте").font(.system(size: 13, weight: .semibold))
                .foregroundColor(PanelColor.good)
        case .failed(let why):
            Text("Не вышло: \(why). Claude остался прежним.").font(.system(size: 13))
                .foregroundColor(PanelColor.bad).fixedSize(horizontal: false, vertical: true)
            SmallButton(title: "Ещё раз") { model.actions.retryUpdate() }
        }
    }
}

private struct StepDot: View {
    enum State { case waiting, running, done }
    let state: State
    @SwiftUI.State private var turn = false
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        ZStack {
            switch state {
            case .waiting:
                Circle().strokeBorder(PanelColor.sub.opacity(0.5), lineWidth: 1.2)
            case .running:
                Circle().trim(from: 0, to: 0.28).stroke(accent, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .rotationEffect(.degrees(turn ? 360 : 0))
                    .onAppear { withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { turn = true } }
            case .done:
                Circle().fill(PanelColor.good)
                Text("✓").font(.system(size: 10, weight: .bold)).foregroundColor(PanelColor.ink)
            }
        }
        .frame(width: 16, height: 16)
        .animation(PanelSpring.press, value: state)
    }
}

private struct RaceView: View {
    @ObservedObject var model: PanelModel
    let race: ClaudeUpdateMenu.Race
    let startedAt: Date?
    let memory: LaneMemory
    let title: String
    let note: String
    let stop: () -> Void
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        let elapsed = startedAt.map { model.now.timeIntervalSince($0) } ?? 0
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PanelColor.text)
                Spacer()
                Text("\(race.percent) %").font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(accent)
            }
            HStack {
                Text(PimpPanelText.raceSubtitle(race, elapsed: elapsed)).font(.system(size: 11))
                    .foregroundColor(PanelColor.sub)
                Spacer()
                Text(PimpPanelText.elapsedText(elapsed)).font(.system(size: 11, design: .monospaced))
                    .foregroundColor(PanelColor.sub)
            }
            ForEach(PimpPanelText.orderedLanes(race.lanes), id: \.id) { lane in
                LaneRow(lane: lane, revived: memory.isRevived(lane.id, at: model.now))
            }
            HStack(alignment: .top) {
                Text(note)
                    .font(.system(size: 11)).foregroundColor(PanelColor.sub).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                LinkButton(title: "остановить", color: PanelColor.sub, action: stop)
            }
        }
    }
}

private struct LaneRow: View {
    let lane: ClaudeUpdateMenu.Lane
    let revived: Bool
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        let off = isOff
        let fraction = lane.total.map { $0 > 0 ? min(1, Double(lane.bytes) / Double($0)) : 0 } ?? 0
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(PimpPanelText.laneName(lane)).font(.system(size: 11, weight: .semibold))
                    .foregroundColor(PanelColor.text)
                if let badge = PimpPanelText.laneBadge(lane, revived: revived) {
                    Text(badge).font(.system(size: 10, weight: .semibold))
                        .foregroundColor(badgeInk)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(badgeFill))
                        .help(failure ?? "")
                        .transition(.opacity)
                }
                Spacer()
                Text(off ? "—" : ClaudeUpdateMenu.speedText(lane.bytesPerSec))
                    .font(.system(size: 11, design: .monospaced)).foregroundColor(PanelColor.sub)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule().fill(fill).frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 6)
            .animation(.linear(duration: 0.25), value: fraction)
            Text(PimpPanelText.bytesText(lane.bytes, total: lane.total)).font(.system(size: 11, design: .monospaced))
                .foregroundColor(PanelColor.sub)
        }
        .opacity(off ? 0.42 : 1)
        .animation(.easeInOut(duration: 0.3), value: off)
    }

    private var isOff: Bool {
        switch lane.state {
        case .dropped, .failed: return true
        default: return false
        }
    }

    private var failure: String? {
        if case .failed(let why) = lane.state { return why }
        return nil
    }

    private var fill: Color {
        switch lane.state {
        case .leading, .won: return accent
        case .running: return PanelColor.sub
        case .dropped, .failed: return PanelColor.frame
        }
    }

    private var badgeFill: Color {
        if revived || lane.state == .won { return PanelColor.good.opacity(0.2) }
        switch lane.state {
        case .leading: return accent
        default: return Color.white.opacity(0.1)
        }
    }

    private var badgeInk: Color {
        if revived || lane.state == .won { return PanelColor.good }
        return lane.state == .leading ? PanelColor.ink : PanelColor.sub
    }
}
