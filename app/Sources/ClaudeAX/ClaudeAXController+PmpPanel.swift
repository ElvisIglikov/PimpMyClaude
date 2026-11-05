import AppKit
import ApplicationServices

extension ClaudeAXController {
    // MARK: - панель PMP: проекты, «Отправить», цвета (WF126)

    /// Снимок проектов панели: обход папок — в фоне, ответ — на главной нити.
    public func panelProjects(_ done: @escaping (PanelSnapshot) -> Void) {
        let recent = knownProjects(limit: 20).filter { ProjectIndex.isDirectory($0.folder) }
            .map { (folder: $0.folder, name: $0.name) }
        let main = mainProjectSetting()
        let root = StatusFeed.projectsRoot()
        DispatchQueue.global(qos: .utility).async {
            let now = Date()
            // Терминальные чаты (WF129, #9077): живые tmux-сессии `rick-<проект>`; tmux нет — пусто. С #10315 — и когда
            // в них было движение, а живые страницы и память времени содержимого сводок решают, что идёт сейчас.
            let activity = PanelTiles.terminalActivity()
            let snapshot = PanelProjects.snapshot(root: root, recent: recent, mainEntry: main, now: now,
                                                  terminals: Set(activity.keys),
                                                  activeTerminals: PanelTiles.activeTerminals(activity, now: now),
                                                  pages: FlowPagesBox.shared.pages(now: now), seen: .shared,
                                                  muted: MutedWaitsStore.shared.current())
            DispatchQueue.main.async { done(snapshot) }
        }
    }

    /// Работа вне страниц Claude (WF234, `WorkNow`): идущие Workflow и терминальные чаты — из той же сводки и того же
    /// кэша на 10 с, что отдаёт страницам `/digest`, своего обхода папок нет; терминалы в ходе (#10460) — свой
    /// взгляд на низ каждой сессии `rick-*` (`PanelTiles.turningTerminals`). Ответ — на главной нити; nil — сводку
    /// прочесть не вышло.
    public func projectsWork(_ done: @escaping (ProjectsWork?) -> Void) {
        let root = StatusFeed.projectsRoot()
        htmlOpener.digest.get { data in
            let turning = PanelTiles.turningTerminals(Set(PanelTiles.terminalActivity().keys)).count
            let work = (try? JSONDecoder().decode(DigestBody.self, from: data)).flatMap {
                ProjectsDigest.work($0, rootExists: FileManager.default.fileExists(atPath: root.path), now: Date(),
                                    turning: turning)
            }
            DispatchQueue.main.async { done(work) }
        }
    }

    /// Темы развёрнутого «Оформления» (WF174, #9182): `PanelColorTiles.strips` раскладывает их по цветовому кругу,
    /// с WF210 — сперва тёмные, светлые в конце. Тем нет в каталоге — не рисуются.
    public static let panelThemeIDs = PanelColorTiles.lightIDs + PanelColorTiles.darkIDs

    public var panelThemes: [WindowColorChip] {
        Self.panelThemeIDs.compactMap { id in actions.themes.first { $0.id == id } }.map(WindowColorChip.init)
    }

    /// Все темы каталога по его порядку — имя выбранной в строке «Цвет Claude» (#9040).
    public var panelAllThemes: [WindowColorChip] { actions.themes.map(WindowColorChip.init) }

    /// Что выбрано у окон сейчас: тема всем окнам, «по проектам» или «как у Claude».
    public var windowColor: WindowColorChoice {
        if let id = actions.themeStore.allThemeID { return .theme(id) }
        return projectPaint.enabled ? .byProject : .plain
    }

    /// Клик по кружку. «По проектам» снимает вид всем окнам, только если он стоит (иначе слои проекта
    /// снялись бы, а отпечатки остались — поправка критика 7).
    public func chooseWindowColor(_ choice: WindowColorChoice) {
        switch choice {
        case .byProject:
            if actions.hasAllWindowsView { actions.resetAllColor() }
            projectPaint.setEnabled(true)
        case .plain:
            projectPaint.setEnabled(false)
            actions.resetAllColor()
        case .theme(let id):
            guard let theme = actions.themes.first(where: { $0.id == id }) else { return }
            actions.applyTheme(scope: Notices.themeScopeAll, theme: .set(theme), window: nil)
        }
    }

    /// Живой фон всем окнам (#9115) — слой `look.aurora` scope `all`, тот же путь, что «Живой фон» в «Всем окнам ▸».
    public var liveBackground: Bool { actions.themeStore.allLook.aurora }

    /// Схема живого фона всем окнам (WF145, схемы WF146): живой фон включается вместе с выбором.
    public var liveScheme: String { actions.themeStore.allLook.schemeID }

    /// Переключатель «Живой» блока «Оформление» (WF180): живой фон в тонах цвета окон или тот же цвет без движения.
    public func setLive(_ on: Bool) {
        applyLiveLook(PanelColorTiles.liveLook(actions.themeStore.allLook, on: on))
    }

    /// Движение живого фона всем окнам (#9994); фон выключен — что стоит в записи (умолчание — «стоит»).
    public var liveMotion: LookMotion { actions.themeStore.allLook.motion }

    /// Строка «Живой фон» панели (#9994): nil — выключить, иначе — живой фон с этим движением.
    public func setLiveMotion(_ motion: LookMotion?) {
        applyLiveLook(PanelColorTiles.liveLook(actions.themeStore.allLook, motion: motion))
    }

    /// «Схема» под «Живым фоном» (WF237: выбор переехал из меню жёлтой кнопки «🎨 Схема ▸»): вид целиком с живым
    /// фоном и этой схемой (`Look.withScheme`) — выбрать схему значит и включить живой фон; движение остаётся.
    public func setLiveScheme(_ id: String) {
        if let next = PanelColorTiles.schemeLook(actions.themeStore.allLook, id: id) { applyLiveLook(next) }
    }

    // MARK: - «Оформление» панели: текст окон (WF237, бывшее меню жёлтой кнопки)

    /// «Плотный текст» всем окнам — слой `look.dense` scope `all`, прочие эффекты вида как были.
    public var denseText: Bool { actions.themeStore.allLook.dense }

    public func setDenseText(_ on: Bool) { actions.setAllDense(on) }

    /// Шрифты каталога для строки «Шрифт» — по секциям прежнего меню (без засечек, рукописные, моноширинные,
    /// с засечками).
    public var panelFonts: [WindowFontChip] {
        PanelColorTiles.fontSections.flatMap { section in
            actions.fonts.filter { $0.category.rawValue == section.id }
                .map { WindowFontChip(id: $0.id, name: $0.displayName, family: $0.family, section: section.id) }
        }
    }

    /// Шрифт всем окнам; nil — «Как у Claude».
    public var windowFontID: String? { actions.themeStore.allFontID }

    public func setWindowFont(_ id: String?) { actions.setAllFont(id: id) }

    /// Размер текста ответов всем окнам (половина `answer`); nil — «как у Claude».
    public var windowTextSize: Int? { actions.themeStore.allSize?.answer }

    public func setWindowTextSize(_ px: Int?) { actions.setAllTextSize(px) }

    /// «Прятать инструменты» (WF120) — команда `hide-tools` всем окнам; ключа нет — включено.
    public var hideTools: Bool { actions.hideToolsEnabled }

    public func setHideTools(_ on: Bool) { actions.setHideTools(on) }

    /// «Прятать код и планы» (#7976) — команда `hide-code` всем окнам; ключа нет — выключено.
    public var hideCode: Bool { actions.hideCodeEnabled }

    public func setHideCode(_ on: Bool) { actions.setHideCode(on) }

    /// Умолчания новой установки (WF210, #9378; слово Элвиса 10.10.2026: «Как только Пимп устанавливается, сразу же
    /// включается живое оформление»); с 03.11.2026 — «Серая» без живого фона всем окнам. Зовёт `AppDelegate` один раз — когда
    /// `PanelColorTiles.isNewInstall`.
    public func applyNewInstallLook() {
        guard let theme = actions.themes.first(where: { $0.id == PanelColorTiles.newInstallThemeID }) else { return }
        actions.applyNewInstallLook(theme: theme, look: PanelColorTiles.liveLook(Look(), on: false))
    }

    private func applyLiveLook(_ look: Look) {
        actions.applyTheme(scope: Notices.themeScopeAll, look: look.layer, window: nil)
    }

    /// Примерка наведением в окне Claude в фокусе; nil — снять примерку.
    public func previewWindowColor(_ choice: WindowColorChoice?) {
        switch choice {
        case nil: actions.endPreview(window: nil)
        case .plain?: actions.previewTheme(nil, window: nil)
        case .theme(let id)?:
            if let theme = actions.themes.first(where: { $0.id == id }) { actions.previewTheme(theme, window: nil) }
        case .byProject?: break
        }
    }
}
