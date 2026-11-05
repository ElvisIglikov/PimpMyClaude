import AppKit
import ClaudeAX

// «Не напоминать» у «Ждёт тебя» (#9820): нажатие в блоке Workflow → запись `muted-waits.json` (`MutedWaitsStore`),
// затем снимок проектов и значок у часов перечитываются сразу — ✋ уходит, не дожидаясь круга панели (20 с) и значка
// (30 с). `/digest` догонит за 10 с (кэш), сводка для полоски (StatusFeed) — за 60 с.

extension AppDelegate {
    func wireMutedWaits() {
        panel.model.actions.muteWait = { [weak self] key, until in
            let written = MutedWaitsStore.shared.mute(key, until: until)
            if written { self?.refreshMutedWaits() }
            return written
        }
        panel.model.actions.unmuteWait = { [weak self] key in
            MutedWaitsStore.shared.unmute(key)
            self?.refreshMutedWaits()
        }
    }

    private func refreshMutedWaits() {
        ax.panelProjects { [weak self] snapshot in
            guard let self = self else { return }
            if self.panel.model.projects != snapshot { self.panel.change { self.panel.model.projects = snapshot } }
            self.refreshIcon()
        }
    }
}
