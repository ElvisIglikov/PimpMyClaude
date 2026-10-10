import AppKit
import ClaudeAX
import SwiftUI

/// Живая часть панели PMP (WF126, `docs/wf126-spec.md` §2.3–2.9): снимок проектов, цвета окон и акцент. Разбор и тексты — `PanelProjects` (ClaudeAX).
final class PanelFeed {
    /// Перечитывать проекты, пока панель открыта.
    static let refreshSeconds: TimeInterval = 20
    /// Примерка цвета окна — не чаще.
    static let previewSeconds: TimeInterval = 0.15

    private let ax: ClaudeAXController
    private let panel: PimpPanelController
    /// Смена акцента — перерисовать значок у часов.
    var onAccent: () -> Void = {}

    private var refreshTimer: Timer?
    private var previewWanted: WindowColorChoice?
    private var previewScheduled = false
    private var previewAt = Date.distantPast
    private var previewing = false

    init(ax: ClaudeAXController, panel: PimpPanelController) {
        self.ax = ax
        self.panel = panel
    }

    private var model: PanelModel { panel.model }

    // MARK: открыть / закрыть

    func opened() {
        refresh()
        refreshColors()
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: Self.refreshSeconds, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    /// Закрылась — примерки снимаются.
    func closed() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        model.accentPreview = nil
        previewWindowColor(nil)
    }

    func refresh() {
        ax.panelProjects { [weak self] snapshot in
            guard let self = self else { return }
            guard self.model.projects != snapshot else { return }
            self.panel.change { self.model.projects = snapshot }
        }
    }

    private func refreshColors() {
        let themes = ax.panelThemes
        if model.windowThemes != themes { model.windowThemes = themes }
        let all = ax.panelAllThemes
        if model.allThemes != all { model.allThemes = all }
        let choice = ax.windowColor
        model.windowColor = choice
        let live = ax.liveBackground
        if model.liveBackground != live { model.liveBackground = live }
        let scheme = ax.liveScheme
        if model.liveScheme != scheme { model.liveScheme = scheme }
        if case .theme(let id) = choice, !all.contains(where: { $0.id == id }) {
            model.foreignTheme = ax.themeName(id)
        } else {
            model.foreignTheme = nil
        }
    }

    // MARK: Esc (§1.6)

    /// Порядок — приоритет: примерка цвета (её снимаем и закрываем панель), выбор цвета PMP, лист настроек.
    func escape() -> Bool {
        if model.accentPreview != nil || previewing { return false }
        if model.accentOpen {
            panel.change { model.accentOpen = false }
            return true
        }
        // «Цвет Claude» (WF141): раскрытый блок — в строку.
        if model.colorsOpen {
            panel.change { model.colorsOpen = false }
            PanelColorTiles.setOpen(false)
            return true
        }
        if model.sheet == .settings {
            panel.showSheet(.panel)
            return true
        }
        return false
    }

    // MARK: цвета (§2.3, §5)

    func chooseWindowColor(_ choice: WindowColorChoice) {
        if previewing {
            ax.previewWindowColor(nil)
            previewing = false
        }
        previewWanted = nil
        ax.chooseWindowColor(choice)
        model.windowColor = choice
        model.foreignTheme = nil
        // WF180: «Живой» не снимается — живой фон переходит на тона нажатого цвета (схема «Как у темы»).
        if PanelColorTiles.colorNeedsLiveScheme(live: model.liveBackground, scheme: model.liveScheme) {
            setLive(true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.refreshColors() }
    }

    /// Переключатель «Живой» (WF180): включить — живой фон в тонах цвета окон, выключить — тот же цвет статично.
    func setLive(_ on: Bool) {
        ax.setLive(on)
        model.liveBackground = on
        if on { model.liveScheme = PanelColorTiles.liveScheme }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.refreshColors() }
    }

    /// Наведение — примерка в окне Claude в фокусе (не чаще раза в 150 мс, уходит последняя); nil — снять.
    func previewWindowColor(_ choice: WindowColorChoice?) {
        let wanted = choice == .byProject ? nil : choice
        guard wanted != nil || previewing || previewScheduled else { return }
        previewWanted = wanted
        guard !previewScheduled else { return }
        previewScheduled = true
        let wait = max(0, Self.previewSeconds - Date().timeIntervalSince(previewAt))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self = self else { return }
            self.previewScheduled = false
            self.previewAt = Date()
            if let choice = self.previewWanted {
                self.ax.previewWindowColor(choice)
                self.previewing = true
            } else if self.previewing {
                self.ax.previewWindowColor(nil)
                self.previewing = false
            }
        }
    }

    func setAccent(_ accent: PMPAccent) {
        UserDefaults.standard.set(accent.rawValue, forKey: PMPAccent.key)
        model.accent = accent
        model.accentPreview = nil
        onAccent()
    }
}
