import AppKit
import ApplicationServices

extension ClaudeAXController {
    // MARK: - WF84: «Новый чат», Авто-Allow

    func connectWF84Menus() {
        // «💬 Новый чат» (#7072): модель донора — из его файла сессии (чат главного окна — из резолвера окна).
        actions.chatModel = { [weak self] chat in self?.index.session(for: chat)?.model }
        actions.autoAllowOn = { [weak self] in self?.autoAllowSwitch.on ?? false }
        // Кнопка в чате (#7246): окна с заголовками, у каждого свой короткий срок ответа; клик — путь «💬 Новый чат».
        // Главное окно (гейт 26.09): метку ставит вложенная страница claude.ai, а заголовок окна
        // остаётся «Claude» — к его заголовку добавляются заголовки его страниц (`ContinueWebAreas`; попапу не
        // нужно — у него заголовок страницы и есть заголовок окна, #7889).
        continueWatch.windows = { [weak self] in
            guard let self = self, AX.isTrustedCached else { return [] }
            let windows = self.app.windows().compactMap { window -> (window: AXUIElement, title: String)? in
                AX.timeout(window, PimpLock.titleTimeout)
                return AX.string(window, kAXTitleAttribute).map { (window: window, title: $0) }
            }
            return self.continueWatch.pages.titles(of: windows, now: Date.timeIntervalSinceReferenceDate)
        }
        continueWatch.onContinue = { [weak self] window in self?.actions.handoffNewChat(window) }
    }
}
