import AppKit
import ApplicationServices

/// Окно ChatGPT глазами расстановки (WF94, #7732, #7651): AX-элемент и рамка в перевёрнутых
/// координатах, как у окон Claude.
struct ChatGPTWindow {
    let element: AXUIElement
    let title: String
    let frame: CGRect
    var id: CGWindowID = 0
    var pid: pid_t = 0
}

/// ChatGPT — ОТДЕЛЬНЫЙ список окон (WF94): в `pimpWindows`, автопокраску, темы, снимок К5,
/// `layout-save` и `close-window` он не входит. Его знают только «Расставить» (правая полоса
/// экрана, где стоят окна Claude), место нового окна и ответ `windows` канала «Пимп».
///
/// Окно берётся одно — переднее: стандартное (`AXStandardWindow`), не свёрнутое, не во весь
/// экран, на экране сейчас и в слое 0; окон два и больше — остальные не трогаем.
///
/// Тот же механизм держит и полосу Chrome (WF120, #7962): второй экземпляр со своим bundle id.
final class ChatGPTWindows {
    /// ChatGPT.app нового рантайма и старый — оба (живой замер 26.09: `com.openai.codex`).
    static let chatGPTBundleIDs: Set<String> = ["com.openai.codex", "com.openai.chat"]

    /// Чьи окна: по умолчанию ChatGPT, у полосы Chrome — `HtmlChromeOpener.chromeBundleID`.
    let bundleIDs: Set<String>

    init(bundleIDs: Set<String> = ChatGPTWindows.chatGPTBundleIDs) {
        self.bundleIDs = bundleIDs
    }

    /// Самая широкая рамка, которой ChatGPT ответил на просьбу сузиться, на этом запуске Пимпа
    /// (Electron зажимает ширину по своему минимуму, 26.09 — 703 pt). По ней «не влезет»
    /// видно заранее, и на узком экране окно не дёргается туда-обратно при каждом ⌥⌘A.
    private(set) var learnedMinWidth: CGFloat = 0

    /// Переднее окно ChatGPT; nil — ChatGPT не запущен, спрятан или окон на экране нет.
    func front() -> ChatGPTWindow? {
        let apps = NSWorkspace.shared.runningApplications.filter {
            guard let id = $0.bundleIdentifier else { return false }
            return bundleIDs.contains(id) && !$0.isHidden && !$0.isTerminated
        }
        guard !apps.isEmpty else { return nil }
        let pids = Set(apps.map { $0.processIdentifier })
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        let onScreen = ChatGPTWindows.layerZero(list, pids: pids)
        guard !onScreen.isEmpty else { return nil }
        var standard: [pid_t: [ChatGPTWindow]] = [:]
        for pid in Set(onScreen.map { $0.pid }) { standard[pid] = ChatGPTWindows.standardWindows(pid: pid) }
        // Порядок оконного сервера — спереди назад: первое совпавшее и есть переднее.
        for entry in onScreen {
            let matches = standard[entry.pid]?.filter { ClaudeActions.frameMatches($0.frame, entry.frame) } ?? []
            guard matches.count == 1, var found = matches.first else { continue }
            let quartz = list.filter {
                ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == entry.pid
                    && ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
                    && (($0[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) >= Double(ClaudeApp.minWindowAlpha)
                    && ($0[kCGWindowBounds as String] as? NSDictionary).flatMap {
                        CGRect(dictionaryRepresentation: $0 as CFDictionary)
                    }.map { ClaudeActions.frameMatches($0, entry.frame) } == true
            }
            guard quartz.count == 1,
                  let id = (quartz[0][kCGWindowNumber as String] as? NSNumber)?.uint32Value, id > 0 else { continue }
            found.id = id; found.pid = entry.pid
            return found
        }
        return nil
    }

    /// Поставить окну рамку и прочитать, что вышло. Шире просимого (Electron зажал по своему
    /// минимуму) — окно придвигается правым краем к правому краю просимой рамки: иначе оно
    /// уехало бы за край экрана. nil — AX рамку не отдал.
    func setFrame(_ window: ChatGPTWindow, _ frame: CGRect) -> CGRect? {
        AX.set(window.element, kAXPositionAttribute, point: frame.origin)
        AX.set(window.element, kAXSizeAttribute, size: frame.size)
        AX.set(window.element, kAXPositionAttribute, point: frame.origin)
        guard let now = AX.frame(window.element) else { return nil }
        guard now.width > frame.width + ClaudeActions.frameTolerance else {
            // Встало уже прежнего минимума (ChatGPT научили сужаться) — старое знание забываем.
            if now.width < learnedMinWidth { learnedMinWidth = 0 }
            return now
        }
        learnedMinWidth = max(learnedMinWidth, now.width)
        AX.set(window.element, kAXPositionAttribute,
               point: CGPoint(x: frame.maxX - now.width, y: frame.minY))
        return AX.frame(window.element) ?? now
    }

    /// Read this exact native window, never whichever Chrome window is now at the front.
    /// Closed, hidden, minimized/fullscreen or reused IDs are not an undo target.
    func currentFrame(of window: ChatGPTWindow) -> CGRect? {
        guard window.id > 0, window.pid > 0,
              let app = NSRunningApplication(processIdentifier: window.pid), !app.isHidden, !app.isTerminated,
              app.bundleIdentifier.map({ bundleIDs.contains($0) }) == true,
              let same = Self.standardWindows(pid: window.pid).first(where: { CFEqual($0.element, window.element) })
        else { return nil }
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let matches = info.filter { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == window.id
            && ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == window.pid }
        guard matches.count == 1,
              let bounds = matches[0][kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
              ClaudeActions.frameMatches(same.frame, frame) else { return nil }
        return same.frame
    }

    // MARK: - живой AX

    /// Системные панели «Сохранить»/«Открыть» тоже `AXStandardWindow` (живой замер 26.09: у
    /// ChatGPT висело окно «Сохранить» 881×720 с `AXIdentifier` `save-panel`) — их не двигаем.
    static let panelIdentifiers: Set<String> = ["save-panel", "open-panel"]

    private static func standardWindows(pid: pid_t) -> [ChatGPTWindow] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        return AX.elements(app, kAXWindowsAttribute).compactMap { element in
            // Окна таймаут приложения не наследуют (z3-s01): зависший ChatGPT держал бы тик до 6 с.
            AX.timeout(element, ClaudeActions.axWindowTimeout)
            guard AX.string(element, kAXSubroleAttribute) == kAXStandardWindowSubrole as String,
                  !panelIdentifiers.contains(AX.string(element, kAXIdentifierAttribute) ?? ""),
                  AX.bool(element, kAXMinimizedAttribute) != true,
                  // Во весь экран (WF120, #7962: решение 5) — не трогаем: рамку такому окну не ставят.
                  AX.bool(element, MinimizeMenu.fullScreenAttribute) != true,
                  let frame = AX.frame(element) else { return nil }
            return ChatGPTWindow(element: element, title: AX.string(element, kAXTitleAttribute) ?? "",
                                 frame: frame)
        }
    }

    // MARK: - чистая часть (её гоняют тесты)

    /// Окна слоя 0 этих процессов из списка оконного сервера, спереди назад. Прозрачные и
    /// служебная мелочь мимо — тем же ситом, что у окон Claude.
    static func layerZero(_ list: [[String: Any]], pids: Set<pid_t>) -> [(pid: pid_t, frame: CGRect)] {
        list.compactMap { info in
            guard let owner = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pids.contains(owner),
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 1
            guard !ClaudeApp.isServiceWindow(frame: rect, alpha: alpha) else { return nil }
            return (pid: owner, frame: rect)
        }
    }

    /// Целевая рамка ChatGPT (WF94): правая полоса рабочей области шириной ОДНОГО столбца
    /// Claude — как если бы ChatGPT был ещё одним окном ряда, — но не уже `minCellWidth`.
    static func target(area: CGRect, claudeCount: Int, minCellWidth: CGFloat,
                       gap: CGFloat) -> CGRect {
        let cols = max(1, min(claudeCount + 1,
                              ArrangeLayout.cap(width: area.width, minCellWidth: minCellWidth, gap: gap)))
        let cell = ((area.width - gap * CGFloat(cols - 1)) / CGFloat(cols)).rounded(.down)
        let width = min(area.width, max(minCellWidth, cell))
        return CGRect(x: area.maxX - width, y: area.minY, width: width, height: area.height)
    }

    /// Что остаётся окнам Claude левее ChatGPT, чей левый край на `chatMinX`: область до него
    /// минус зазор. Уже `minCellWidth` — nil: такой резерв не нужен никому.
    static func remainder(area: CGRect, chatMinX: CGFloat, minCellWidth: CGFloat,
                          gap: CGFloat) -> CGRect? {
        let width = min(chatMinX, area.maxX) - gap - area.minX
        guard width >= minCellWidth else { return nil }
        return CGRect(x: area.minX, y: area.minY, width: width, height: area.height)
    }

    /// Резерв правой полосы (WF94, #7732): ChatGPT стоит на экране, где расставляются окна
    /// Claude, — ему целевая рамка, фактическую (Electron зажмёт по своему минимуму) читаем
    /// обратно, и окнам Claude на этом экране остаётся область левее неё. Экран без окон
    /// Claude, ChatGPT ни на одном экране, остаток уже `minCellWidth` (SOTSU 800 при 703) —
    /// ChatGPT не резервируем и не двигаем (а сдвинули и не влезло — ставим обратно).
    ///
    /// `set` ставит рамку и отдаёт ту, что вышла; nil — AX отказал. Отдаёт экраны для
    /// `ArrangeLayout.smart` (у экрана ChatGPT рабочая область урезана) и рамку ChatGPT,
    /// если резерв состоялся.
    ///
    /// `keepCells` — полоса Chrome (WF120, #7962, критик: на Одиссее с ChatGPT иначе 8→6 столбцов):
    /// резерв только если ни одно окно Claude этого экрана не теряет из-за него ячейку умной
    /// сетки; иначе Chrome не трогаем (сдвинули и не влезло — ставим обратно).
    static func reserve(screens: [(full: CGRect, usable: CGRect)], claude: [CGRect],
                        chatGPT: CGRect, knownMinWidth: CGFloat = 0, minCellWidth: CGFloat,
                        gap: CGFloat, keepCells: Bool = false, anchor: CGRect? = nil, set: (CGRect) -> CGRect?)
        -> (screens: [(full: CGRect, usable: CGRect)], chatGPT: CGRect?) {
        let center = CGPoint(x: chatGPT.midX, y: chatGPT.midY)
        guard let screen = screens.firstIndex(where: { $0.full.contains(center) }) else {
            return (screens, nil)
        }
        if let anchor = anchor,
           Screens.assign(screens: screens.map { $0.full }, frames: [anchor]).first != screen { return (screens, nil) }
        let homes = Screens.assign(screens: screens.map { $0.full }, frames: claude)
        let mine = homes.filter { $0 == screen }.count
        guard mine > 0 else { return (screens, nil) }
        let area = screens[screen].usable
        let room: (CGRect) -> Int = {
            min(mine, ArrangeLayout.smartCells(count: mine, in: $0, minCellWidth: minCellWidth, gap: gap).count)
        }
        let enough: (CGRect?) -> CGRect? = { rest in
            guard let rest = rest, !keepCells || room(rest) >= mine else { return nil }
            return rest
        }
        var want = target(area: area, claudeCount: mine, minCellWidth: minCellWidth, gap: gap)
        // Уже известно, что уже `knownMinWidth` ChatGPT не станет: цель сразу его ширины у
        // правого края (проверка гейта WF94) — стоящий на месте ChatGPT с ней совпадёт и не
        // дёрнется, а не уедет за край на время зажима. Остатка не хватит — не трогаем вовсе.
        if knownMinWidth > want.width {
            let width = min(area.width, knownMinWidth)
            want = CGRect(x: area.maxX - width, y: want.minY, width: width, height: want.height)
        }
        guard enough(remainder(area: area, chatMinX: want.minX,
                               minCellWidth: minCellWidth, gap: gap)) != nil else { return (screens, nil) }
        let actual: CGRect
        if ClaudeActions.frameMatches(chatGPT, want) {
            actual = chatGPT
        } else {
            guard let got = set(want) else { return (screens, nil) }
            actual = got
        }
        guard let rest = enough(remainder(area: area, chatMinX: actual.minX, minCellWidth: minCellWidth,
                                          gap: gap)) else {
            // Electron зажал шире, чем влезает (или Chrome отнял бы ячейку окну Claude):
            // окно встаёт как стояло, резерва нет.
            if !ClaudeActions.frameMatches(actual, chatGPT) { _ = set(chatGPT) }
            return (screens, nil)
        }
        var out = screens
        out[screen] = (full: screens[screen].full, usable: rest)
        return (out, actual)
    }
}
