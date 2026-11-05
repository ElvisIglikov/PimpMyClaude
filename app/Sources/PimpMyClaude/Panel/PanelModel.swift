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
        hex(ColorMath.rgb(hex: value) ?? 0x2B2A27)
    }
    // Графит (WF103, DESIGN.md): серые фон, линии и текст; акцент с WF126 выбирается (`pmpAccent`).
    static let text = hex(0xECECEE)
    static let sub = hex(0x9B9BA1)
    static let bad = hex(0xD9695F)
    static let warn = hex(0xEFC65C)
    static let ink = hex(0x1C1C1E)
    static let frame = hex(0x3A3A3D)
    static let panel = hex(0x262628)
    static let danger = hex(0xEEA39E)

    /// «Хорошо» цветом акцента; красный и янтарь совпали бы с `bad` и `warn`, у них норма цветом текста.
    static func good(_ accent: Color) -> Color {
        accent == hex(PMPAccent.red.hex) || accent == hex(PMPAccent.amber.hex) ? text : accent
    }
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
    var patch: () -> Void = { PanelActions.unwired("patch") }
    var findClaude: () -> Void = { PanelActions.unwired("findClaude") }
    var patchLog: () -> Void = { PanelActions.unwired("patchLog") }
    var download: () -> Void = { PanelActions.unwired("download") }
    var update: () -> Void = { PanelActions.unwired("update") }
    var updateAnyway: () -> Void = { PanelActions.unwired("updateAnyway") }
    var wait: () -> Void = { PanelActions.unwired("wait") }
    var updateNow: () -> Void = { PanelActions.unwired("updateNow") }
    /// «При запуске» и «Отменить» у отложенного обновления Claude (WF283).
    var nextLaunch: () -> Void = { PanelActions.unwired("nextLaunch") }
    var cancelNextLaunch: () -> Void = { PanelActions.unwired("cancelNextLaunch") }
    var cancelRace: () -> Void = { PanelActions.unwired("cancelRace") }
    var retryUpdate: () -> Void = { PanelActions.unwired("retryUpdate") }
    var toggle: (String) -> Void = { _ in PanelActions.unwired("toggle") }
    var sendDelay: (_ on: Bool, _ seconds: Int) -> Void = { _, _ in PanelActions.unwired("sendDelay") }
    var previewSendDelay: (_ seconds: Int) -> Void = { _ in PanelActions.unwired("previewSendDelay") }
    /// Группа «Закреплённые» (#8743): название проекта и таймер у закреплённых чатов.
    var pinnedLook: (PinnedLook) -> Void = { _ in PanelActions.unwired("pinnedLook") }
    /// «Бэкап чатов» (#7729, WF94): все чаты Claude Code одним zip на склад.
    var archiveChats: () -> Void = { PanelActions.unwired("archiveChats") }
    /// «PimpViewer» (WF97): лента всех HTML и фото чатов.
    var showViewer: () -> Void = { PanelActions.unwired("showViewer") }
    /// «Поставить Рика» и «Показать в Finder» (WF216).
    var installRick: () -> Void = { PanelActions.unwired("installRick") }
    var revealRick: () -> Void = { PanelActions.unwired("revealRick") }
    /// «Поставить сторож» (пожелания 03.11, раздел 0).
    var installKontekst: () -> Void = { PanelActions.unwired("installKontekst") }
    /// «Обновлять Пимп и Viewer самим» (WF217, К-SU).
    var selfUpdate: (Bool) -> Void = { _ in PanelActions.unwired("selfUpdate") }
    var setup: () -> Void = { PanelActions.unwired("setup") }
    /// «Поддержать автора» (WF108, #8179): окно из настроек.
    var donate: () -> Void = { PanelActions.unwired("donate") }
    var about: () -> Void = { PanelActions.unwired("about") }
    var uninstall: () -> Void = { PanelActions.unwired("uninstall") }
    var quit: () -> Void = { PanelActions.unwired("quit") }
    // WF126: цвета.
    var windowColor: (WindowColorChoice) -> Void = { _ in PanelActions.unwired("windowColor") }
    var previewWindowColor: (WindowColorChoice?) -> Void = { _ in PanelActions.unwired("previewWindowColor") }
    /// Строка «Живой фон» блока «Оформление» (#9994): nil — без живого фона, иначе — он с этим движением.
    var live: (LookMotion?) -> Void = { _ in PanelActions.unwired("live") }
    /// Дополнительное оформление (WF237, бывшее меню жёлтой кнопки): схема живого фона, «Плотный текст», шрифт
    /// (nil — как у Claude), размер ответов (nil — как у Claude), «Прятать инструменты». Всем окнам.
    var scheme: (String) -> Void = { _ in PanelActions.unwired("scheme") }
    var dense: (Bool) -> Void = { _ in PanelActions.unwired("dense") }
    var windowFont: (String?) -> Void = { _ in PanelActions.unwired("windowFont") }
    var textSize: (Int?) -> Void = { _ in PanelActions.unwired("textSize") }
    var zoom: (ClaudeZoom) -> Void = { _ in PanelActions.unwired("zoom") }
    var hideTools: (Bool) -> Void = { _ in PanelActions.unwired("hideTools") }
    var hideCode: (Bool) -> Void = { _ in PanelActions.unwired("hideCode") }
    var setAccent: (PMPAccent) -> Void = { _ in PanelActions.unwired("setAccent") }
    /// Esc: true — обработан (отсчёт, поле, лист настроек), панель остаётся.
    var escape: () -> Bool = { PanelActions.unwired("escape"); return false }
    // WF126 §7: лист «Настройки».
    var enterKeys: (EnterKeys) -> Void = { _ in PanelActions.unwired("enterKeys") }
    /// Звук отсчёта (WF151): пункт подменю «🔊 Звук отсчёта ▸».
    var countdownSound: (CountdownSound) -> Void = { _ in PanelActions.unwired("countdownSound") }
    /// Вид отсчёта (К1 v3, #9041): пункт подменю «🚀 Вид отсчёта ▸».
    var sendLookStyle: (String) -> Void = { _ in PanelActions.unwired("sendLookStyle") }
    /// Размер отсчёта, проценты 60…200 (WF242): ползунок в настройках выбранной плитки.
    var sendLookSize: (Int) -> Void = { _ in PanelActions.unwired("sendLookSize") }
    /// «Анализ памяти» (WF242): поручение из файла — в поле ввода окна Claude, без отправки; «Изменить текст» —
    /// открыть этот файл.
    var memoryAnalysis: () -> Void = { PanelActions.unwired("memoryAnalysis") }
    var editMemoryPrompt: () -> Void = { PanelActions.unwired("editMemoryPrompt") }
    var bypassNew: (Bool) -> Void = { _ in PanelActions.unwired("bypassNew") }
    /// Блок «Текст» (WF167, #9168): по ширине (true) или влево; поля по бокам 0…40.
    var textJustify: (Bool) -> Void = { _ in PanelActions.unwired("textJustify") }
    var sidePadding: (Int) -> Void = { _ in PanelActions.unwired("sidePadding") }
    /// «Чистые ответы» (WF210, #9398, К-CA): строки расхода и состояния под ответами спрятаны.
    var cleanAnswers: (Bool) -> Void = { _ in PanelActions.unwired("cleanAnswers") }
    var openClaudeSettings: () -> Void = { PanelActions.unwired("openClaudeSettings") }
    /// Вариант значка (WF180): одна картинка из нескольких.
    var iconVariant: (StatusIcon.Variant) -> Void = { _ in PanelActions.unwired("iconVariant") }
    /// Мастер доступов (#10310): «Открыть», «Назад»/«Далее», «Позже», «Не надо», перезапуск PMP.
    var accessWizard: (AccessWizardAction) -> Void = { _ in PanelActions.unwired("accessWizard") }
    /// «Не напоминать» у «Ждёт тебя» (#9820): записать (false — не вышло) и снять запись.
    var muteWait: (_ key: String, _ until: Date?) -> Bool = { _, _ in PanelActions.unwired("muteWait"); return false }
    var unmuteWait: (String) -> Void = { _ in PanelActions.unwired("unmuteWait") }

    /// Нажатие, которому `AppDelegate.wirePanel()` не дал дела (#10527, «кнопка отвалилась от проводки»): строка в
    /// журнал и запись в `unwiredLog` — по ней тест проводки ловит пропуск. Главная нитка.
    static func unwired(_ name: String) {
        unwiredLog.append(name)
        NSLog("PimpMyClaude: кнопка панели «%@» ни к чему не подключена", name)
    }
    static var unwiredLog: [String] = []
}

/// Группа листа «Настройки» (§7): открыта всегда одна.
enum SettingsGroup { case text, font, enter, chats, pinned, windows, updates, more }

final class PanelModel: ObservableObject {
    enum Phase { case folded, popped, open }
    /// Лист панели: сама панель или «Настройки» за шестерёнкой (§7).
    enum Sheet { case panel, settings }

    @Published var phase = Phase.folded
    @Published var sheet = Sheet.panel
    @Published var patch: StatusIcon.Patch = .unknown
    /// Доступы Claude в macOS (#10252): слетели — карточка над блоками; `.unknown` — Пимпу базу не прочитать.
    @Published var access: ClaudeAccess.State = .ok
    /// Мастер доступов в карточке (#10310): шаги, текущий, «Готово ✓» — ведёт `AccessWizardController`.
    @Published var wizard = AccessWizard.Snapshot()
    @Published var limits: ClaudeLimits?
    @Published var update: PimpPanelText.UpdateBlock = .none
    /// Версия, чью карточку обновления скрыли крестиком (#10765); переживает перезапуск, новая версия — карточка снова.
    @Published var hiddenUpdateVersion = UserDefaults.standard.string(forKey: PimpPanelText.updateHiddenKey) {
        didSet { UserDefaults.standard.set(hiddenUpdateVersion, forKey: PimpPanelText.updateHiddenKey) }
    }
    var updateCardHidden: Bool { PimpPanelText.updateCardHidden(update, hidden: hiddenUpdateVersion) }
    /// Проверка окна после обновления Claude нашла поломки (#10527): строка в блоке обновления; зелёная — nil.
    @Published var liveCheckLine: String?
    @Published var readySize: String?
    /// Идущая установка Claude откроет его после (false — отложенное при закрытом Claude, WF283).
    @Published var installOpensClaude = true
    @Published var raceStartedAt: Date?
    @Published var lanes = LaneMemory()
    @Published var toggles: [PanelToggle] = []
    @Published var sendDelay = SendDelaySetting()
    @Published var sendDelayLine: String?
    /// Масштаб окон Claude в процентах; nil — страница ещё не сказала.
    @Published var claudeZoom: Int?
    @Published var pinnedLook = PinnedLook()
    @Published var maxCardHeight: CGFloat = 800
    @Published var patchRun = PatchRun.idle
    /// Надпись кнопки под ошибкой патча вместо «Ещё раз» (#9842: «Открыть настройки» — повтор сам откроет их и подождёт).
    @Published var patchFix: String?
    /// Что прервёт закрытие Claude патчем (WF234, `PimpPanelText.patchWorkNote`); работы не видно — nil.
    @Published var patchWorkNote: String?
    /// Найденную версию PMP уже отказался ставить (второй замок Electron, G2 WF101): блок
    /// «доступна» пишет «PimpMyClaude пока не патчит Claude X» без кнопки «Скачать».
    @Published var refusedVersion: String?
    /// Бэкап чатов собирается (WF97 Б5s, #7772): строка «Бэкап чатов — идёт…», нажатия нет.
    @Published var archiving = false
    @Published var rick = RickInstall.hidden
    @Published var kontekst = KontekstInstall.ok
    /// Автообновление Пимпа и Viewer (WF217, К-SU): переключатель, тихая строка под ним и строка «обновился».
    @Published var selfUpdate = SelfUpdateDriver.Look()
    @Published var now = Date()
    /// Где по X у панели значок — оттуда вылет.
    @Published var anchorX: CGFloat = 170
    /// «Поддержать автора» (WF108): окну есть что показать (иначе строки нет).
    @Published var donateAvailable = false
    /// Когда кнопку «Поддержать автора» у «Изменить виджеты» скрыли крестиком (слово 03.11.2026); переживает перезапуск.
    @Published var donateHiddenAt = UserDefaults.standard.object(forKey: PanelModel.donateHiddenKey) as? Date {
        didSet { UserDefaults.standard.set(donateHiddenAt, forKey: Self.donateHiddenKey) }
    }
    static let donateHiddenKey = "panelDonateHiddenAt"
    /// Через столько скрытая кнопка возвращается: 100 часов.
    static let donateReturnAfter: TimeInterval = 100 * 3600
    /// Кнопку есть куда вести и её не скрывали или срок вышел. Режим правки — забота самой строки.
    static func donateButtonShown(available: Bool, hiddenAt: Date?, now: Date) -> Bool {
        guard available else { return false }
        guard let hiddenAt = hiddenAt else { return true }
        return now.timeIntervalSince(hiddenAt) >= donateReturnAfter
    }
    // WF126
    @Published var accent = PMPAccent.current
    @Published var accentPreview: PMPAccent?
    /// Снимок проектов; nil — ещё не читали («Читаю проекты…»).
    @Published var projects: PanelSnapshot?
    @Published var windowThemes: [WindowColorChip] = []
    /// Все темы каталога — имя выбранной не из десяти в строке «Цвет Claude» (#9040).
    @Published var allThemes: [WindowColorChip] = []
    /// Дополнительное оформление за шестерёнкой в строке «Оформление» (WF242): «Живой фон».
    @Published var colorsExtraOpen = false
    /// Ряд «Отсчёт»: над какой плиткой курсор и какая играет свой вид; с какого момента играет.
    @Published var countdownHover = CountdownHover()
    var countdownSince = Date()
    /// Настройки выбранного вида отсчёта выпали под рядом (второе нажатие по выбранной плитке).
    @Published var countdownSettingsOpen = false
    @Published var sendLookSize = SendLook.defaultSize
    /// Строка под кнопкой «Анализ памяти»: почему не вставилось; nil — обычная подпись.
    @Published var memoryStarterNote: String?
    /// Живой фон всем окнам включён (слой `look.aurora` scope `all`).
    @Published var liveBackground = false
    /// Движение живого фона всем окнам (#9994); нет ключа — «стоит».
    @Published var liveMotion = LookMotion.still
    /// Схема живого фона всем окнам (`LookScheme`, WF145); нет ключа — умолчание.
    @Published var liveScheme = LookScheme.defaultID
    /// Текст окон (WF237): «Плотный текст», шрифт и размер ответов всем окнам, «Прятать инструменты».
    @Published var denseText = false
    @Published var windowFonts: [WindowFontChip] = []
    @Published var windowFontID: String?
    @Published var windowTextSize: Int?
    @Published var hideTools = true
    /// «Прятать код и планы» (#7976): по умолчанию выключено.
    @Published var hideCode = false
    /// Выбор цвета PMP под шапкой — нажатием на значок слева вверху (#9020 п. 3–5).
    @Published var accentOpen = false
    /// Вид значка у часов — тот же значок в шапке панели.
    @Published var iconLook: StatusIcon.Look?
    @Published var windowColor = WindowColorChoice.byProject
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
    /// Блок Workflow раскрыт (WF258; с #10239 — блок PMP Tray для Windows); панель открывается свёрнутой.
    @Published var workflowOpen = false
    /// Блок Workflow (#10239): фильтр по счёту, открытая карточка, страницы — не помнятся, панель открылась — «идут».
    @Published var flow = WorkflowBlock.State()
    /// Цены Workflow по API (#6282, `WorkflowCostRunner`); ещё не считали — nil. Не сбрасываются при открытии панели.
    @Published var flowCosts: WorkflowCosts?
    /// «Впереди · N» раскрыто — помнится, как `WorkflowAheadOpen` на Windows.
    @Published var aheadOpen = UserDefaults.standard.bool(forKey: PanelModel.aheadKey) {
        didSet { UserDefaults.standard.set(aheadOpen, forKey: Self.aheadKey) }
    }
    static let aheadKey = "workflowAheadOpen"
    /// Над счётом блока Workflow показана легенда — блок поднят над соседями (`WidgetBoard`).
    @Published var workflowLegend = false
    /// Нагрузка на память за 3 ч (#9082, WF164); пусто — плитки нет. Приходит, только пока панель открыта.
    @Published var memory: [MacMemorySample] = []
    /// Кто съел память (#11620): три главных под подписью графика; пусто — строки нет.
    @Published var memoryEaters: [MemoryEater] = []
    /// Процессор и видеокарта за 3 ч (#10308, `MacLoad`); пусто — плиток нет (выключено или датчики молчат).
    @Published var macLoad: [MacLoadSample] = []
    /// Режим правки блоков (файл 53, вариант 2, слово Элвиса 22.10.2026: «Изменить виджеты… Вот это классно»):
    /// блоки покачиваются, «−» скрывает, кружок справа — ширина, блок тащится сразу; «Готово» или Esc — выход.
    @Published var editingWidgets = false
    /// Токены за 7 дней по копилке Рика (WF157, #9149; WF170 — несобранный день nil); nil — файла нет, плитки нет.
    @Published var tokenSpark: TokenSpark?
    /// Плитка «Токены» — окно с графиком рядом с панелью.
    var openTokens: () -> Void = {}
    /// Блоки-виджеты (WF129, #9043): порядок и ширина, перетаскивание; «Workflow списком» раскрыт. Раскладка, сохранённая
    /// до порядка #10308, перед чтением один раз встаёт в новый порядок (`reorderOnce`).
    @Published var layout: PanelWidgetLayout = {
        PanelWidgetLayout.reorderOnce()
        return PanelWidgetLayout.load()
    }()
    /// Открытые терминалы проектов (#10464) — карточка сверху; пусто — карточки нет.
    @Published var terminals: [PanelTerminal] = []
    /// Предохранитель iTerm держит (#10976) — почему окна не открываются; строка в блоке «Терминалы».
    @Published var terminalsAlarm: String?
    /// Нажатие строки терминала — его окно Terminal.
    var showTerminal: (PanelTerminal) -> Void = { _ in }
    /// Право управлять Терминалом (#10464) — строка «Окна и Mac».
    @Published var terminalAccess: PanelTerminals.Access = .notAsked
    var askTerminalAccess: () -> Void = {}
    @Published var widgetDrag: PanelWidgetDrag?
    /// Когда отпустили перетаскиваемый блок: отпускание мыши после переноса — не нажатие по свёрнутой строке.
    var widgetDragEnded = Date.distantPast
    /// Вариант значка (WF180; до того WF129 — проекты, WF174 — три выключателя).
    @Published var iconVariant = StatusIcon.variant()
    /// Шрифт панели (WF255): выбор в «Настройках», по умолчанию 2.4.
    @Published var typography = PanelTypography.saved()
    /// Значки других программ, что не влезли в строку меню (WF270, #10264); собираются при открытии панели.
    @Published var menuExtras: [MenuBarExtras.Item] = []
    var pressExtra: (MenuBarExtras.Item) -> Void = { _ in }
    /// С какой температуры градусы у часов (#10289); выбор — «Окна и Mac» в настройках.
    @Published var tempMin = StatusIcon.tempMin()
    var pickTempMin: (Int) -> Void = { _ in }
    /// «Повторять при ошибке сервера» (#6936): выключатель и интервал в «Дополнительно»; выбор — `pickAutoRetry`.
    @Published var autoRetryOn = AutoRetry.isOn()
    @Published var autoRetryEvery = AutoRetry.every()
    var pickAutoRetry: (Bool, Int) -> Void = { _, _ in }
    /// Значок отпустили (#10280): точка экрана Cocoa (снизу слева главного экрана) — перенести в строку меню.
    var dropExtra: (MenuBarExtras.Item, CGPoint) -> Void = { _, _ in }
    /// #10304: правая кнопка или Ctrl+клик — меню программы; значок отпустили между значками полосы — встать рядом с
    /// соседом (true — после него). Глифы значков (снимки окон, #10301) — по `Item.id`, вместе со списком.
    var pressExtraSecondary: (MenuBarExtras.Item) -> Void = { _ in }
    var reorderExtra: (MenuBarExtras.Item, MenuBarExtras.Item, Bool) -> Void = { _, _, _ in }
    @Published var extraImages: [String: NSImage] = [:]
    /// Строка под рядом «Не влезли»: подсказка при перетаскивании, «Переношу…», отказ.
    @Published var extraNote: String?
    var loader = 7
    /// Высота карточки — клик по тени и пустому холсту тоже «мимо».
    var cardHeight: CGFloat = 44
    var appVersion = ""
    var reduceMotion = false
    var actions = PanelActions()

    /// Лимиты для показа: свежие, а нет — последние известные (#9824); `limitsAge` — их давность, свежие — nil.
    var known: ClaudeLimits? { StatusIcon.known(limits) }
    var limitsAge: String? { StatusIcon.staleText(limits, now: now) }
    var shownAccent: PMPAccent { accentPreview ?? accent }

    /// Панель открывается — раскрытое внутри блоков свёрнуто (WF242): шестерёнка «Оформления» и настройки отсчёта,
    /// карточка Workflow. Свёрнут или развёрнут сам блок — раскладка, её ставит `foldBlocksForOpen` (с 22.10.2026 у
    /// графиков нет своей свёртки — файл 53, раздел 4).
    func foldSections() {
        colorsExtraOpen = false
        countdownSettingsOpen = false
        countdownHover = CountdownHover()
        editingWidgets = false
        workflowOpen = false
        flow = WorkflowBlock.State()
        workflowLegend = false
        memoryStarterNote = nil
    }

    /// Панель открывается одним видом (слово 03.11.2026): «Неделя · Сброс» развёрнуты, «5 часов», Fable и остальное —
    /// строками, что бы ни развернули в прошлый раз. Без анимации: окно ещё не показано.
    func foldBlocksForOpen() {
        var next = layout
        next.setDefaultFolds(visible: Set(layout.items.map { $0.id }))
        guard next != layout else { return }
        layout = next
        next.save()
    }

    /// Блоки с графиком (файл 53, раздел 4; слово Элвиса 22.10.2026: «все должны так же раскрываться, как
    /// температура… память, процессор»): свёрнут — строка «Имя › число», развёрнут — строка «Имя ⌄ число» и график
    /// под ней. Своей свёртки у графика нет — это свёртка блока в раскладке.
    static let chartWidgets: [PanelWidget] = [.temperature, .memory, .cpu, .gpu]

    /// Блок развёрнут (не свёрнут в строку).
    func opened(_ widget: PanelWidget) -> Bool { layout.item(widget.rawValue)?.collapsed == false }

    /// Прежние имена «график раскрыт» (кадры и тесты): развёрнут ли блок; запись — раскладка без сохранения.
    var temperatureOpen: Bool {
        get { opened(.temperature) }
        set { layout.setCollapsed(PanelWidget.temperature.rawValue, !newValue) }
    }
    var memoryOpen: Bool {
        get { opened(.memory) }
        set { layout.setCollapsed(PanelWidget.memory.rawValue, !newValue) }
    }
    var loadOpen: Bool {
        get { opened(.cpu) || opened(.gpu) }
        set {
            layout.setCollapsed(PanelWidget.cpu.rawValue, !newValue)
            layout.setCollapsed(PanelWidget.gpu.rawValue, !newValue)
        }
    }

    /// Развёрнутые блоки с графиком и «Оформление» — в сетке своим рядом во всю ширину (`PanelWidgetLayout.rows`):
    /// графики разных блоков стоят друг под другом, края сходятся; полосы цветов и плитки отсчёта в половину панели
    /// не встают. Свёрнутой строкой — половинкой рядом с соседом.
    var expandedWidgets: Set<String> {
        Set((Self.chartWidgets + [.colors]).map { $0.rawValue }).filter { layout.item($0)?.collapsed == false }
    }

    /// «Изменить виджеты» / «Готово» (файл 53, вариант 2). Выход — и тянутый блок встаёт, где отпустили.
    func setEditingWidgets(_ on: Bool) {
        guard editingWidgets != on else { return }
        if !on { endWidgetDrag() }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : PanelSpring.settings) { editingWidgets = on }
    }

    /// Esc в правке — выйти из неё; не в правке — false.
    func escapeEditing() -> Bool {
        guard editingWidgets else { return false }
        setEditingWidgets(false)
        return true
    }

    /// Шеврон или строка названия: свернуть развёрнутый блок, развернуть свёрнутый.
    func toggleCollapsed(_ id: String) {
        setCollapsed(id, layout.item(id)?.collapsed != true)
    }

    /// Общая ось времени графиков температуры и памяти: от самой ранней точки до самой поздней — подписи часов и
    /// правые края двух графиков стоят друг под другом.
    var chartDomain: ChartDomain? {
        let firsts = [temperature.first?.at, memory.first?.at].compactMap { $0 }
        let lasts = [temperature.last?.at, memory.last?.at].compactMap { $0 }
        guard let first = firsts.min(), let last = lasts.max() else { return nil }
        return ChartDomain(first: first, last: last)
    }

    /// Общее левое поле графиков (#9818): по самой широкой подписи шкалы обоих — поля начинаются на одной линии.
    var chartLeft: CGFloat {
        ChartFrame.left(labels: MacTemperature.scale(temperature).ticks.map(MacTemperature.degrees)
                        + MacMemory.axis(total: memory.last?.total ?? 0).map { $0.label })
    }

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
        widgetDragEnded = Date()
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

    /// «Шрифт панели» (WF255): вся панель сразу этим набором, выбор помнится.
    func chooseTypography(_ type: PanelTypography, defaults: UserDefaults = .standard) {
        guard type != typography else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : PanelSpring.settings) { typography = type }
        PanelTypography.save(type, defaults)
    }

    /// Свернуть блок в строку или развернуть (WF269, #10205): свёрнутость побеждает раскрытый график.
    func setCollapsed(_ id: String, _ collapsed: Bool) {
        if collapsed { foldOpen([id]) }
        changeLayout { $0.setCollapsed(id, collapsed) }
    }

    /// Нажатие по свёрнутой строке — блок разворачивается (слово Элвиса 22.10.2026 про «Оформление»: «открывается
    /// странно» — развернуть можно было только значком, который появляется через 0,8 с над заголовком). Мышь отпустили
    /// после переноса блока — это не нажатие.
    func tapCollapsed(_ id: String, now: Date = Date()) {
        guard widgetDrag == nil, now.timeIntervalSince(widgetDragEnded) > 0.3 else { return }
        setCollapsed(id, false)
    }

    /// «Свернуть всё» / «Развернуть всё» в шапке (WF269).
    func setAllCollapsed(_ collapsed: Bool, visible: Set<String>) {
        if collapsed { foldOpen(visible) }
        changeLayout { $0.setAllCollapsed(collapsed, visible: visible) }
    }

    private func foldOpen(_ ids: Set<String>) {
        if ids.contains(PanelWidget.workflow.rawValue) { workflowOpen = false }
        if ids.contains(PanelWidget.colors.rawValue) { colorsExtraOpen = false; countdownSettingsOpen = false }
    }

    /// Образец цвета окон у свёрнутого «Оформления» (фон и акцент темы); «по проектам» и «как у Claude» — nil.
    var colorsSwatch: WindowColorChip? {
        guard case .theme(let id) = windowColor else { return nil }
        return allThemes.first { $0.id == id }
    }

    /// Главное число свёрнутого блока справа от заголовка: «53°», «49 %», «24 %»; числа нет — nil.
    func collapsedValue(_ widget: PanelWidget) -> String? {
        let percent: (Int) -> String = { "\($0)\u{00A0}%" }
        switch widget {
        case .week: return StatusIcon.limit(.week, in: known).map { percent($0.used) }
        case .limits: return StatusIcon.limit(.fiveHour, in: known).map { percent($0.used) }
        case .fable: return StatusIcon.limit(.fable, in: known).map { percent($0.used) }
        // #11165: короткой записью «9 ч 40 мин» — «9 часов 40 минут» в половинку не входило и резалось «…».
        case .reset: return PanelShort.left(StatusIcon.limit(.week, in: known)?.resetsAt, now: now)
        case .temperature: return temperature.last?.value.map(MacTemperature.degrees)
        // #11166: та же мера, что в раскрытом блоке, — «20 ГБ», а не нагрузка macOS «51 %» рядом с «20 ГБ» из 24.
        case .memory: return memory.last?.value == nil ? nil : MacMemory.nowText(memory)
        case .tokens: return tokenSpark?.todayText
        case .cpu: return macLoad.last?.cpu.map(MacLoad.percentText)
        case .gpu: return macLoad.last?.gpu.map(MacLoad.percentText)
        case .workflow: return workflowGroups.map(WorkflowBlock.countsLine)
        case .terminals: return TerminalsText.collapsed(terminals, now: now)
        // Слово Элвиса 22.10.2026: «Оформление… должно показывать изначально… какой цвет установлен».
        // Цвета по проектам в панели больше нет (слово 03.11.2026: «своё у каждого проекта, убери эту тему»).
        case .colors:
            return windowColor == .byProject ? nil : PanelColorTiles.shownName(hovered: nil, choice: windowColor, themes: allThemes)
        }
    }

    /// Цвет числа свёрнутой строки (слово Элвиса 22.10.2026: «когда хорошие, мы зелёным красим… заходит в эту
    /// панельку, у него всё зелёное»): пороги те же, что у раскрытых графиков (#9818) — температура по оценке macOS,
    /// память по давлению и свопу, процессор и видеокарта: до 70 % зелёный, до 90 % жёлтый, дальше красный.
    /// nil — цветом текста, как раньше.
    func collapsedTone(_ widget: PanelWidget) -> Color? {
        let good = PanelColor.hex(shownAccent.hex)
        switch widget {
        case .temperature:
            guard let last = temperature.last, last.value != nil else { return nil }
            return chartColor(MacTemperature.health(last), good: good)
        case .memory: return memory.last?.value == nil ? nil : MacMemory.health(memory).last.map { chartColor($0, good: good) }
        case .cpu: return macLoad.last?.cpu.map { chartColor(MacLoad.health($0), good: good) }
        case .gpu: return macLoad.last?.gpu.map { chartColor(MacLoad.health($0), good: good) }
        default: return nil
        }
    }

    // MARK: блок Workflow (#10239)

    /// Группы строк блока по снимку проектов; ещё не читали — nil.
    var workflowGroups: WorkflowBlock.Groups? { projects.map { WorkflowBlock.groups($0, now: now) } }

    private func flowAnimation() -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : PanelSpring.settings
    }

    /// Раскрыть или свернуть блок (нажатие шапки).
    func toggleWorkflow() {
        withAnimation(flowAnimation()) {
            workflowOpen.toggle()
            if !workflowOpen { flow.card = nil }
        }
    }

    /// Нажатие числа в шапке: свёрнут — раскрыть с этой группой; другое — его группа, то же ещё раз — снова «идут».
    func pickWorkflowFilter(_ key: WorkflowBlock.Filter) {
        if let groups = workflowGroups { flow.settle(groups) }
        withAnimation(flowAnimation()) {
            if flow.pick(key, open: workflowOpen) { workflowOpen = true }
        }
    }

    func openWorkflowCard(_ id: String) {
        withAnimation(flowAnimation()) { flow.card = id }
    }

    /// Esc и ✕: карточка — назад к списку. true — было что закрывать.
    @discardableResult
    func closeWorkflowCard() -> Bool {
        guard flow.card != nil else { return false }
        withAnimation(flowAnimation()) { flow.card = nil }
        return true
    }

    /// ← → и стрелки карточки: соседний Workflow группы, на краю — стоп. true — карточка открыта (клавиша съедена).
    @discardableResult
    func turnWorkflowCard(_ step: Int) -> Bool {
        guard let groups = workflowGroups, let group = flow.cardGroup(groups) else { return false }
        turnWorkflowCard(to: (group.firstIndex { $0.id == flow.card } ?? 0) + step, in: group)
        return true
    }

    func turnWorkflowCard(to index: Int, in group: [WorkflowBlock.Row]) {
        var next = flow
        guard next.turn(to: index, in: group) else { return }
        // Направление въезда — до смены страницы: уходящая уезжает в ту же сторону.
        flow.slide = next.slide
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.24)) { flow = next }
    }

    /// Страница списка (или «Впереди»).
    func turnWorkflowPage(_ step: Int, ahead: Bool) {
        withAnimation(.easeOut(duration: 0.15)) {
            if ahead { flow.aheadPage = max(0, flow.aheadPage + step) } else { flow.page = max(0, flow.page + step) }
        }
    }

    /// Крестик карточки обновления (#10765): эта версия молчит до следующей; «Обновить» остаётся в «Настройках».
    func hideUpdateCard() {
        guard let card = PimpPanelText.updateCard(update, size: nil) else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : PanelSpring.settings) { hiddenUpdateVersion = card.version }
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
