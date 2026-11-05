import AppKit
import ClaudeAX
import Patcher

/// «Обновить при следующем запуске» (#10765, WF283): карточка готового обновления сворачивается в строку, а само
/// обновление встаёт, как только Claude не запущен — человек его закрыл, PMP запустился без него — или когда PMP сам
/// перезапускает Claude (`restart-claude`). Закрытый человеком Claude не поднимаем; открыли его, пока шла установка
/// (она его закрывает ради целого бандла), — открываем снова, когда встала.
extension AppDelegate {
    /// «При запуске» на карточке.
    func planNextLaunch() {
        guard case .ready(let version) = claudeUpdate.phase else { return }
        UserDefaults.standard.set(version, forKey: PimpPanelText.updatePlannedKey)
        updateExtras.question = nil
        offering = nil
        refreshUpdateBlock()
        installPlannedIfClaudeClosed()
    }

    /// «Отменить» в свёрнутой строке: снова полная карточка.
    func cancelNextLaunch() {
        UserDefaults.standard.removeObject(forKey: PimpPanelText.updatePlannedKey)
        refreshUpdateBlock()
        evaluateOffer()
    }

    /// Готовое обновление этой копии, если его отложили «При запуске» и ставить его сейчас можно
    /// (`installPlannedNow`); иначе nil. `restarting` — PMP сам перезапускает Claude.
    func plannedPrepared(for url: URL, restarting: Bool = false) -> PreparedClaudeUpdate? {
        // По пути: `bundleURL` запущенного Claude (`restart-claude`) и копия из `claudeUpdateTarget` — разные URL.
        guard case .ready(let version) = claudeUpdate.phase, let target = claudeUpdateTarget(),
              target.standardizedFileURL.path == url.standardizedFileURL.path,
              let ready = readyClaude, ready.url == target else { return nil }
        let running = !restarting && !ClaudeUpdater(appURL: url).runningPIDs().isEmpty
        let now = PimpPanelText.installPlannedNow(
            planned: UserDefaults.standard.string(forKey: PimpPanelText.updatePlannedKey), ready: version,
            claudeRunning: running, restarting: restarting,
            pimpBusy: busy || claudeDownload != nil || readyRechecks > 0 || askingPages)
        return now ? ready.prepared : nil
    }

    /// Claude не запущен и обновление отложено — ставим сейчас, без вопроса и не открывая Claude.
    func installPlannedIfClaudeClosed() {
        guard let url = claudeUpdateTarget(), let prepared = plannedPrepared(for: url) else { return }
        claudeOpenedDuringPlanned = false
        plannedInstallRunning = true
        let started = installClaude(prepared, url: url, relaunch: false) { [weak self] _ in
            guard let self = self else { return }
            self.plannedInstallRunning = false
            guard self.claudeOpenedDuringPlanned else { return }
            self.claudeOpenedDuringPlanned = false
            // Открыли до подмены — установщик его не тронул (`claudeOpened`), открывать нечего.
            guard ClaudeUpdater(appURL: url).runningPIDs().isEmpty else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
        if !started { plannedInstallRunning = false }
    }

    /// Claude запустился или вышел (NSWorkspace). Вышел — через секунду (дочерние процессы тоже уходят) пробуем
    /// отложенное; запустился посреди такой установки — запомнить, чтобы открыть после.
    func claudeLaunchedOrQuit(launched: Bool) {
        if launched {
            if plannedInstallRunning { claudeOpenedDuringPlanned = true }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.installPlannedIfClaudeClosed() }
    }
}
