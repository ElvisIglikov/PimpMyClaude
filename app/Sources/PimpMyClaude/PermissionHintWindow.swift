import AppKit
import ClaudeAX
import Patcher
import SwiftUI

// Подсказка «Включи PimpMyClaude в «Управление приложениями»» (#9842, слово Элвиса 12.10.2026: «Сделай, чтобы Пимп
// гарантированно патчил… люди же не разберутся»). Окна «Разрешить» у этого права на новых macOS нет: шаг записи
// (`ClaudePatcher.waitForWritable`) пишет `Patcher.appManagementWaitLine`, приложение открывает настройки на нужной
// странице и ставит эту плашку рядом с их окном. Панель у часов для этого не годится: она закрывается, как только
// человек щёлкает в настройки. Право дали — шаг сам едет дальше, плашка уходит. Плашка — пузырёк со стрелкой к окну
// настроек: подлетает к нему и «дышит» к нему, уходит растворением (`HintPullDriver`, #9841).
// С #10310 текст, кнопки и плитки — параметром (`PermissionHintContent`): та же плашка ведёт мастер доступов
// (`AccessWizardController`) — внутри окна настроек справа снизу, как у Gemini, со стрелкой «↑» и плитками PMP и Claude.

/// Плашка: поверх окон и на всех рабочих столах, фокус у настроек не забирает.
final class PermissionHintPanel: NSPanel {
    init(view: PermissionHintView) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        level = .floating
        isOpaque = false
        hasShadow = true
        backgroundColor = .clear
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        appearance = NSAppearance(named: .darkAqua)
        contentView = PermissionHintHost(rootView: view)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Первое нажатие по плашке — уже действие.
final class PermissionHintHost: NSHostingView<PermissionHintView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Что на плашке: заголовок, нумерованные шаги, примечание, плитки, кнопки и ссылка перезапуска (#10310).
struct PermissionHintContent: Equatable {
    struct Tile: Equatable {
        let url: URL
        let title: String
    }

    var title: String
    /// «↑» перед заголовком и крестик в углу — как у Gemini; кнопок «Открыть настройки»/«Отмена» тогда нет.
    var gemini = false
    var steps: [String] = []
    var note: String?
    var tiles: [Tile] = []
    var link: String?

    /// «Управление приложениями» (#9842) — слово в слово как было.
    static let appManagement = PermissionHintContent(
        title: "Включи PimpMyClaude",
        steps: ["В настройках «Управление приложениями» щёлкни переключатель у PimpMyClaude.",
                "Нет его в списке — нажми «+» под списком и выбери PimpMyClaude в «Программах».",
                "macOS спросит пароль Мака или предложит «Закрыть и открыть снова» — соглашайся."],
        note: "Патч продолжится сам — нажимать «Пропатчить» ещё раз не надо.",
        link: "Включил, а патч стоит — перезапустить PMP")
}

struct PermissionHintView: View {
    static let width: CGFloat = 330
    var content = PermissionHintContent.appManagement
    let openSettings: () -> Void
    let relaunch: () -> Void
    let cancel: () -> Void
    /// Стрелка к окну настроек; nil — окна рядом нет. Поле под стрелку есть всегда (`hintPointer`).
    var pointer: HintPull.Side?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !content.steps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(content.steps.enumerated()), id: \.offset) { index, text in step("\(index + 1)", text) }
                }
            }
            if let note = content.note {
                Text(note).font(.system(size: 11)).foregroundColor(PanelColor.sub).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(content.tiles, id: \.url) { tile in AppDragTile(url: tile.url, title: tile.title) }
            if !content.gemini {
                HStack(spacing: 8) {
                    Button("Открыть настройки", action: openSettings).keyboardShortcut(.defaultAction)
                    Button("Отмена", action: cancel)
                    Spacer(minLength: 0)
                }
            }
            if let link = content.link {
                Button(action: relaunch) {
                    Text(link).font(.system(size: 11)).underline().foregroundColor(PanelColor.sub)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: Self.width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Self.fill))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Self.border, lineWidth: 1))
        .hintPointer(pointer, fill: Self.fill, stroke: Self.border, lineWidth: 1)
    }

    private static let fill = PanelColor.hex(0x1F1F22)
    private static let border = Color.white.opacity(0.14)

    @ViewBuilder private var header: some View {
        if content.gemini {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("↑").font(.system(size: 15, weight: .semibold)).foregroundColor(.accentColor)
                Text(content.title).font(.system(size: 14, weight: .semibold)).foregroundColor(PanelColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(action: cancel) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundColor(PanelColor.sub)
                }
                .buttonStyle(.plain)
                .help("Закрыть")
            }
        } else {
            Text(content.title).font(.system(size: 14, weight: .semibold)).foregroundColor(PanelColor.text)
        }
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(number).font(.system(size: 12, weight: .bold)).foregroundColor(PanelColor.warn)
            Text(text).font(.system(size: 12)).foregroundColor(PanelColor.text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Показ и место плашки: справа от окна Системных настроек, не влезает — слева, нигде — левый нижний угол экрана; окна нет — правый верхний угол.
/// Мастер доступов (#10310) ставит её внутрь окна настроек справа снизу (`Placement.inside`), как у Gemini.
final class PermissionHintController {
    enum Placement { case beside, inside }

    var onRelaunch: () -> Void = {}
    private var panel: PermissionHintPanel?
    private var view: PermissionHintView?
    private var pull: HintPullDriver?
    private var timer: Timer?
    private var settingsLink = SystemSettings.appManagement
    private var placement = Placement.beside
    private var onCancel: () -> Void = {}

    var isShown: Bool { pull?.isShown == true }

    /// Открыть настройки на «Управление приложениями» и встать рядом. Уже стоит — только освежить место.
    func show() {
        show(.appManagement, link: SystemSettings.appManagement, placement: .beside) { Patcher.cancelPermissionWait() }
    }

    /// Открыть лист `link` и поставить плашку с `content`; «Отмена» или крестик — `cancel` и плашка уходит.
    func show(_ content: PermissionHintContent, link: String, placement: Placement, cancel: @escaping () -> Void) {
        settingsLink = link
        self.placement = placement
        onCancel = cancel
        SystemSettings.open(link)
        if panel == nil {
            let view = PermissionHintView(content: content,
                                          openSettings: { [weak self] in if let link = self?.settingsLink { SystemSettings.open(link) } },
                                          relaunch: { [weak self] in self?.onRelaunch() },
                                          cancel: { [weak self] in
                                              self?.onCancel()
                                              self?.hide()
                                          })
            self.view = view
            let panel = PermissionHintPanel(view: view)
            self.panel = panel
            pull = HintPullDriver(window: panel)
        }
        refresh(content)
    }

    /// Новый текст той же плашки — без повторного открытия настроек.
    func refresh(_ content: PermissionHintContent) {
        guard let panel = panel, let host = panel.contentView as? PermissionHintHost, var view = view else { return }
        if view.content != content {
            view.content = content
            self.view = view
            host.rootView = view
        }
        place()
        guard timer == nil else { return }
        // Окно настроек открывается не сразу и его двигают — место пересчитываем раз в секунду.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.place() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        pull?.hide()
    }

    private func place() {
        guard let panel = panel, let host = panel.contentView as? PermissionHintHost, var view = view else { return }
        // Окно — плашка и поле под стрелку со всех сторон: место считается по самой плашке.
        let edge = HintPointer.inset
        let outer = host.fittingSize
        let size = NSSize(width: outer.width - 2 * edge, height: outer.height - 2 * edge)
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let (frame, target) = Self.frame(placement, settings: Self.settingsWindow(), size: size, visible: visible)
        // Слева и справа в Cocoa — те же, что в CG: сторона цели — по самим рамкам.
        let pointer = target.flatMap { HintPull.side(of: $0, from: frame) }
        if view.pointer != pointer {
            view.pointer = pointer
            self.view = view
            host.rootView = view
        }
        pull?.show(at: frame.insetBy(dx: -edge, dy: -edge), toward: target.map { NSPoint(x: $0.midX, y: $0.midY) })
    }

    /// Место плашки (Cocoa) и окно, к которому стрелка (nil — стрелки нет и плашка не «дышит»: внутри окна настроек её
    /// плитку ловят мышью). `inside` — справа снизу в окне настроек, как у Gemini; не влезает — как `beside`.
    static func frame(_ placement: Placement, settings: NSRect?, size: NSSize, visible: NSRect) -> (NSRect, NSRect?) {
        let edge: CGFloat = 16
        if placement == .inside, let settings = settings {
            let inner = settings.intersection(visible)
            if inner.width >= size.width + 2 * edge, inner.height >= size.height + 2 * edge {
                return (NSRect(x: inner.maxX - size.width - edge, y: inner.minY + edge, width: size.width, height: size.height),
                        nil)
            }
        }
        var origin = NSPoint(x: visible.maxX - size.width - edge, y: visible.maxY - size.height - edge)
        var target: NSRect?
        if let settings = settings {
            let right = settings.maxX + 12
            let left = settings.minX - 12 - size.width
            if right + size.width <= visible.maxX || left >= visible.minX {
                origin.x = right + size.width <= visible.maxX ? right : left
                origin.y = min(max(settings.maxY - size.height, visible.minY), visible.maxY - size.height)
                target = settings
            } else {
                // Сбоку не влезает (ноутбук): левый нижний угол экрана — поверх бокового меню настроек; переключатели
                // справа и «+» под списком остаются открыты. Показывать стрелкой не на что.
                origin = NSPoint(x: visible.minX + edge, y: visible.minY + edge)
            }
        }
        return (NSRect(origin: origin, size: size), target)
    }

    /// Рамка окна Системных настроек в координатах Cocoa; nil — окна нет на экране.
    private static func settingsWindow() -> NSRect? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        let primary = NSScreen.screens.first?.frame.height ?? 0
        for info in list where (info[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier
            && (info[kCGWindowLayer as String] as? Int) == 0 {
            guard let raw = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: raw as CFDictionary), bounds.width > 200 else { continue }
            return NSRect(x: bounds.minX, y: primary - bounds.maxY, width: bounds.width, height: bounds.height)
        }
        return nil
    }
}
