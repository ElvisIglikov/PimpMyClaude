import Foundation

extension ClaudeAXController {
    // MARK: - блок Workflow — только живое (#10315)

    /// Живые страницы для правила «идёт сейчас» (`PanelProjects.isLive`): main и popout со свежим ответом (не старше
    /// `ChatProbe.workingSeconds`), которые работают (видна кнопка «стоп») или чья строка состояния говорит «идёт».
    /// Папка — по индексу сессий для чата страницы, у главного окна на домашнем экране — по его чипу (как у покраски).
    /// Кладутся в `FlowPagesBox` на каждом тике — их читают сборки панели и `/digest` со своих очередей.
    func noteFlowPages() {
        let now = Date()
        let pages = chatProbe.pages.compactMap { page -> FlowPage? in
            guard page.kind != .other, now.timeIntervalSince(page.at) < ChatProbe.workingSeconds else { return nil }
            let working = page.working == true
            let running = page.flow?.state == "run"
            guard working || running else { return nil }
            let home = page.kind == .main ? page.folder.map { index.root(of: URL(fileURLWithPath: $0)) } : nil
            let folder = page.chat.flatMap { index.folder(for: $0) } ?? home
            return FlowPage(folder: folder?.standardizedFileURL.path, project: page.flow?.project ?? "",
                            working: working, running: running)
        }
        FlowPagesBox.shared.set(pages, at: now)
    }
}
