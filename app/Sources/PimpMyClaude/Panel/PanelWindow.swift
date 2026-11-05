import AppKit
import ClaudeAX
import SwiftUI

// MARK: - окно

final class PimpPanelController {
    static let width: CGFloat = 340
    /// Запас холста под тень и свечение по бокам.
    static let margin: CGFloat = 48

    let model = PanelModel()
    /// Окно «Токены по проектам» (WF157) — рядом с карточкой.
    let tokens = TokensWindowController()
    private(set) var window: PimpPanelWindow?
    private weak var button: NSStatusBarButton?
    /// Видимая область экрана под окном значка — от неё холст панели. Тест подставляет область за экраном.
    var screenArea: (NSWindow) -> NSRect = { bar in
        (bar.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 875)
    }
    /// Последние нажатия на значок (#10527, самопроверка `clickLog`): решение и видна ли панель через 150 мс.
    private(set) var clicks: [LiveCheck.Click] = []
    private var monitors: [Any] = []
    private var timer: Timer?
    private var openedAt: TimeInterval = 0
    private var generation = 0
    private(set) var isOpen = false
    /// Пимп сам ⌘-перетаскивает значок в строке меню (#10280): его щелчки — не «мимо».
    var holdOpen = false
    /// Полоска «Не влезли» у часов (#10286) и холст панели без неё: полоска есть — панель ниже на её высоту.
    private lazy var strip = MenuExtrasStrip(model: model)
    private var baseCanvas: NSRect?

    /// Значки «Не влезли» или строка под ними сменились: полоска по ним, панель — под полоской.
    func refreshExtras() {
        let inset = strip.update(open: isOpen)
        guard isOpen, let base = baseCanvas, let window = window else { return }
        let frame = NSRect(x: base.minX, y: base.minY, width: base.width, height: max(200, base.height - inset))
        guard frame != window.frame else { return }
        model.maxCardHeight = frame.height
        model.cardHeight = min(model.cardHeight, frame.height)
        window.setFrame(frame, display: true)
    }
    private var closedAt: TimeInterval = -.infinity
    /// Закрыта меньше секунды назад: запрос «открыть» из окна Claude (#8894) — тот же клик, что её закрыл.
    var closedJustNow: Bool { !isOpen && ProcessInfo.processInfo.systemUptime - closedAt < 1 }
    /// Панель открылась — свежие данные (статус патча, проверка обновления).
    var onOpen: () -> Void = {}
    /// Панель закрылась — вопрос блока обновления снимается (гейт 2 WF87).
    var onClose: () -> Void = {}

    /// Панель правда на экране: считается открытой, окно видно и приложение не спрятано (⌥⌘H «Скрыть остальные» в
    /// другом приложении прячет и окно панели, а `isOpen` остаётся).
    var isShown: Bool { isOpen && window?.isVisible == true && !NSApp.isHidden }

    /// Нажатие по значку. `pressedAt` — время события мыши (тот же отсчёт, что `systemUptime`).
    func toggle(from button: NSStatusBarButton, pressedAt: TimeInterval? = NSApp.currentEvent?.timestamp) {
        let action = PanelClick.action(isOpen: isOpen, shown: isShown, pressedAt: pressedAt, openedAt: openedAt)
        switch action {
        case .open: open(from: button)
        case .close: close()
        case .ignore: break
        }
        noteClick(action)
    }

    /// Запись в кольцо нажатий; видна ли панель — через `LiveCheck.clickSettle` (150 мс). Следом успели нажать ещё раз
    /// (двойной щелчок) — эту запись не судим: панель закрыл уже следующий щелчок.
    private func noteClick(_ action: PanelClick) {
        clicks = LiveCheck.ring(clicks + [LiveCheck.Click(at: Date(), action: "\(action)")])
        let at = clicks[clicks.count - 1].at
        DispatchQueue.main.asyncAfter(deadline: .now() + LiveCheck.clickSettle) { [weak self] in
            guard let self = self, self.clicks.last?.at == at else { return }
            self.clicks[self.clicks.count - 1].shown = self.isShown
        }
    }

    /// Окно полосы «Не влезли», когда оно на экране (самопроверка `stripWindow`).
    var stripFrame: CGRect? { strip.shownFrame }

    func open(from button: NSStatusBarButton) {
        guard let barWindow = button.window else { return }
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        generation += 1
        let generation = generation
        self.button = button
        isOpen = true
        let visible = screenArea(barWindow)
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
            model.foldSections()
            model.foldBlocksForOpen()
            model.now = Date()
            model.anchorX = min(max(center - x, 24), Self.width - 24)
            model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
        onOpen()
        model.openTokens = { [weak self] in self?.showTokens() }
        tokens.spark { [weak self] values in self?.model.tokenSpark = values }
        let window = self.window ?? makeWindow()
        self.window = window
        baseCanvas = canvas
        window.setFrame(canvas, display: true)
        refreshExtras()
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
        strip.hide()
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
            } else if !Self.isStatusItem(event.window) && !TokensWindowController.owns(event.window)
                        && !self.strip.owns(event.window) {
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
        // Щелчок, которым панель открыли, — ещё не «мимо»; щелчки переноса значка (#10280) — тоже.
        guard ProcessInfo.processInfo.systemUptime - openedAt > 0.15, !holdOpen else { return }
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
            // Esc по шагам: перетаскивание, карточка Workflow (#10239), отсчёт и лист настроек, потом панель.
            guard let self = self, !self.model.cancelWidgetDrag(), !self.model.escapeEditing(), !self.model.closeWorkflowCard(),
                  !self.model.actions.escape() else { return }
            self.close()
        }
        window.onArrow = { [weak self] step in self?.model.turnWorkflowCard(step) ?? false }
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
    /// ← → (−1 / +1): листают открытую карточку Workflow (#10239); false — не съедено.
    var onArrow: (Int) -> Bool = { _ in false }
    var onQuit: () -> Void = {}
    var onSettings: () -> Void = {}
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override func cancelOperation(_ sender: Any?) { onEscape() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape(); return }
        if event.keyCode == 123 || event.keyCode == 124, onArrow(event.keyCode == 124 ? 1 : -1) { return }
        super.keyDown(with: event)
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

/// Сколько содержимого уже пролистано вверх, pt (#11164).
private struct ScrollTopKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// #11164 (WF296, S1 №1): панель выше экрана — низ срезан, а полосы прокрутки нет (WF210). Ниже есть ещё — по низу
/// карточки затемнение и шеврон вниз; долистали до конца — их нет.
enum PanelMoreBelow {
    static func shown(content: CGFloat, card: CGFloat, scrolled: CGFloat) -> Bool { content - card - scrolled > 4 }
}

struct PanelRoot: View {
    @ObservedObject var model: PanelModel
    @State private var contentHeight: CGFloat = 44
    @State private var scrollTop: CGFloat = 0

    var body: some View {
        let open = model.phase == .open
        let shown = model.phase != .folded
        let height = open ? min(contentHeight, model.maxCardHeight) : 44
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                PanelBackground()
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
                                .preference(key: ScrollTopKey.self, value: -proxy.frame(in: .named("panelScroll")).minY)
                        })
                }
                    .coordinateSpace(name: "panelScroll")
                    .frame(width: PimpPanelController.width, height: height, alignment: .top)
                    .overlay(alignment: .bottom) {
                        if open, PanelMoreBelow.shown(content: contentHeight, card: height, scrolled: scrollTop) {
                            ZStack(alignment: .bottom) {
                                LinearGradient(colors: [PanelColor.ink.opacity(0), PanelColor.ink],
                                               startPoint: .top, endPoint: .bottom)
                                    .frame(height: 44)
                                Image(systemName: "chevron.compact.down")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(PanelColor.sub)
                                    .padding(.bottom, 4)
                            }
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                            .transition(.opacity)
                        }
                    }
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
        .onPreferenceChange(ScrollTopKey.self) { value in
            guard abs(value - scrollTop) > 0.5 else { return }
            withAnimation(.easeOut(duration: 0.15)) { scrollTop = value }
        }
        .onChange(of: model.maxCardHeight) { value in model.cardHeight = min(contentHeight, value) }
        .environment(\.colorScheme, .dark)
        .environment(\.pmpAccent, PanelColor.hex(model.shownAccent.hex))
        .environment(\.panelType, model.typography)
    }
}

/// Графитовая подложка, обводка, блик по верху и тень холста — без градиента и свечения (WF103). С WF177 (#9192,
/// слово Элвиса 09.10 02:35: всё просвечивает, ничего не разобрать — «сделай, чтоб не просвечивала») подложка сплошная:
/// без стекла `.hudWindow` и без 6 % просвета — рабочий стол и окна под панелью не видны ни в светлой, ни в тёмной теме.
private struct PanelBackground: View {
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

/// Что делает нажатие по значку PMP (слово Элвиса 22.10.2026: «Нажимаю один раз… он не открывается… со второго раза
/// или с третьего начинает открываться»). Две ловушки прежнего `isOpen ? close() : open()`:
///   • панель «открыта», а окна на экране нет (приложение спрятали ⌥⌘H из другого окна) — первое нажатие её
///     «закрывало», и только второе открывало;
///   • пока панель открывалась (главная нитка занята), второе нажатие ждало в очереди и закрывало её сразу, как она
///     показалась, — открывало только третье. Нажатие, отпущенное раньше, чем панель показалась, — не «закрыть».
enum PanelClick: Equatable {
    case open, close, ignore

    static func action(isOpen: Bool, shown: Bool, pressedAt: TimeInterval?, openedAt: TimeInterval) -> PanelClick {
        guard isOpen, shown else { return .open }
        if let pressed = pressedAt, pressed < openedAt { return .ignore }
        return .close
    }
}
