import AppKit
import ApplicationServices

extension ClaudeAXController {
    // MARK: - кружок-микрофон (#7054, контракт К4, батч M2 WF84)

    /// Диктатор сейчас пишет (или запись на паузе) — автообновление Пимпа в такой момент себя не
    /// перезапускает (WF217, К-SU). Спрашиваем самого Диктатора.
    public var isDictating: Bool { micMonitor.dictatorRunning && micMonitor.dictatorState().isRecording }

    func connectMic() {
        micMonitor.pages = { [weak self] in self?.chatProbe.pages ?? [] }
        micMonitor.claudePID = { [weak self] in self?.app.pid }
        micMonitor.windowTitle = { [weak self] frame in
            self?.app.window(matching: frame).flatMap { AX.string($0, kAXTitleAttribute) }
        }
        micMonitor.sendMode = { [weak self] mode in self?.actions.sendMic(mode) ?? false }
        micMonitor.sendRefused = { [weak self] chat, match in
            self?.actions.sendMicRefused(chat: chat, match: match) ?? false
        }
        micMonitor.notice = { [weak self] text in self?.hud.show(text, seconds: 2.5) }
        micMonitor.focusClaude = { [weak self] in self?.app.activate() }
        actions.micMode = { [weak self] in self?.micMonitor.mode ?? .claude }
        // Место значка меняется молча — пока кружок нужен, карта страниц освежается сама.
        chatProbe.isMicWanted = { [weak self] in self?.micMonitor.wantsPages ?? false }
        // Режим `dictator` и кружок виден — раз в 5 с, а не 15 (контракт WF92 (в)).
        chatProbe.isMicFast = { [weak self] in self?.micMonitor.wantsFastPages ?? false }
        // Значок у часов показывает лимиты всегда (WF87): свой круг раз в минуту при любом тумблере.
        chatProbe.isLimitsWanted = { true }
    }
}
