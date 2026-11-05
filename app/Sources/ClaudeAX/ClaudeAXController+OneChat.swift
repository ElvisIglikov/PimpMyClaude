import ApplicationServices
import Foundation

extension ClaudeAXController {
    // MARK: - «Всё в одном чате» панели PMP страницы (#9552, К-OC)

    /// Что делать по `GET /one-chat`. Папка Рика (`RickKit.folder`) — новое окно Claude в ней; по этому пути ничего
    /// нет — к строке «Поставить Рика» (её видно ровно тогда же: `RickKit.isPresent`); там файл или битая ссылка —
    /// ставить некуда и открывать не в чем: сказать плашкой.
    enum OneChatStep: Equatable {
        case window(Project)
        case setup
        case occupied(String)
    }

    static func oneChatStep(folder: URL, fileManager: FileManager = .default) -> OneChatStep {
        if ProjectIndex.isDirectory(folder, fileManager) {
            let place = folder.standardizedFileURL
            return .window(Project(folder: place, name: place.lastPathComponent, lastFocusedAt: 0))
        }
        guard RickKit.isPresent(folder) else { return .setup }
        let path = NSString(string: folder.path).abbreviatingWithTildeInPath
        return .occupied("«\(path)» — не папка: убери этот файл, тогда PMP поставит Рика")
    }

    /// Главная нить: диск читаем здесь, не на очереди порта. Окно — тем же путём, что «🪟 Новое окно ▸ проект» и канал
    /// «Пимп»; второе нажатие, пока первое окно открывается, — плашка «уже открываю» (`refuseNewWindowRepeat`).
    func openOneChat() {
        switch Self.oneChatStep(folder: RickKit.folder) {
        case .setup:
            onRickSetupRequest?()
        case .occupied(let text):
            hud.show(text, seconds: 4)
        case .window(let project):
            guard !actions.refuseNewWindowRepeat() else { return }
            actions.newWindow(in: project, on: nil)
        }
    }
}
