import AppKit
import ClaudeAX
import Patcher

// Проверка окна после обновления Claude и самопроверка Пимпа (#10527, контракт К-HEALTH). Взводит её
// `show(state:)`, ведёт `ClaudeAXController` (круг probe с `health()`), здесь — раздел приложения по замерам своего
// процесса (только чтение) и итог: строка в блоке обновления панели и одно уведомление на версию при красном.

extension AppDelegate {
    func wireLiveCheck() {
        ax.liveCheckApp = { [weak self] in self?.liveCheckSection() }
        ax.onLiveCheckDone = { [weak self] report, file in self?.liveCheckDone(report, file: file) }
    }

    /// Раздел приложения: версия Пимпа, Claude, проверенная версия и пять проверок.
    func liveCheckSection(at: Date = Date()) -> LiveCheck.AppSection {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        var claude = "unknown"
        switch lastState {
        case .installed(let found, _)?, .notInstalled(let found)?, .lost(let found, _)?: claude = found
        case .claudeNotFound?, nil: break
        }
        return LiveCheck.AppSection(version: version, at: at, claude: claude,
                                    checked: UserDefaults.standard.string(forKey: LiveCheck.checkedKey),
                                    checks: LiveCheck.appChecks(liveCheckFacts()))
    }

    /// Замеры: окно значка и экраны, число в значке, полоса «Не влезли», кольцо нажатий, открытая панель.
    func liveCheckFacts() -> LiveCheck.AppFacts {
        let look = panel.model.iconLook
        let known = StatusIcon.known(currentLimits()) != nil && look?.outlined != true && look?.spinner != true
        let number = look.map { $0.number != nil || $0.bars.contains { $0 != nil } } ?? false
        return LiveCheck.AppFacts(
            item: statusItem?.button?.window?.frame,
            screens: NSScreen.screens.map {
                LiveCheck.Screen(frame: $0.frame, left: $0.auxiliaryTopLeftArea, right: $0.auxiliaryTopRightArea)
            },
            statsOn: panel.model.iconVariant.mode != .plain,
            limitsKnown: known,
            iconNumber: number,
            strip: panel.stripFrame,
            clicks: panel.clicks,
            panelOpen: panel.isShown,
            panelAlpha: panel.window?.alphaValue ?? 1,
            // Окно панели — прозрачный холст под тень; фон, который видит человек, — заливка карточки.
            backgroundAlpha: NSColor(PanelColor.ink).alphaComponent)
    }

    /// Итог проверки: строка в блоке обновления панели; красное — одно уведомление с кнопкой «Отчёт».
    func liveCheckDone(_ report: LiveCheck.Report, file: URL?) {
        let line = LiveCheck.panelLine(report)
        if panel.model.liveCheckLine != line { panel.change { panel.model.liveCheckLine = line } }
        guard !report.ok else { return }
        Notifier.postLiveCheck(LiveCheck.notificationText(report), file: file)
    }
}
