import AppKit
import ApplicationServices

extension ClaudeAXController {
    // MARK: - «📦 Архив чатов» (#7729, план WF94 Б2)

    /// Бэкап собирается прямо сейчас: строка панели пишет «идёт…» (WF97 Б5s).
    public var archiveBusy: Bool { chatArchive.isBusy }

    /// Все чаты Claude Code одним zip на склад — в фоне; второй клик во время сборки ничего не
    /// делает. Итог — алертом с «Показать в Finder», отказ — плашкой.
    public func archiveChats() {
        let started = chatArchive.start { [weak self] outcome in
            self?.onArchiveDone?()
            switch outcome {
            case .success(let summary): ChatArchive.presentDone(summary)
            case .failure(let failure):
                self?.hud.show(failure.notice, seconds: Notices.archiveChatsFailSeconds)
            }
        }
        // Второй клик во время сборки — второго zip нет, но и молчать нельзя (#7772): «уже идёт».
        hud.show(started ? Notices.archiveChatsNotice : Notices.archiveChatsBusyNotice,
                 seconds: started ? Notices.archiveChatsNoticeSeconds : Notices.repeatNoticeSeconds)
    }
}
