import CoreGraphics
import Foundation

/// Итог «🙈 Спрятать окна» / «👀 Показать окна» (WF112, #8255): отказ или заголовки окон, которые
/// свернули (развернули). Его отдаёт канал «Пимп» (`hide`/`show`).
public struct WindowHideResult: Equatable {
    /// Отказы — те же слова, что у канала (`PimpChannel.Failure`).
    public enum Failure: String {
        /// Claude не запущен или окон у него нет вовсе.
        case noWindows = "no-windows"
        /// Идёт «Новое окно», возврат снимка К5 или работа канала — окна двигает она.
        case busy
        /// Главное окно (там Рик) не опознано — не прячем ничего, иначе свернули бы его.
        case windowMissing = "window-missing"
    }

    public let failure: Failure?
    /// Заголовки свёрнутых (`hide`) или развёрнутых (`show`) окон.
    public let titles: [String]
    /// Сколько окон во весь экран не тронули (только `hide`).
    public let skipped: Int

    public init(failure: Failure? = nil, titles: [String] = [], skipped: Int = 0) {
        self.failure = failure
        self.titles = titles
        self.skipped = skipped
    }
}

/// Чистая часть «спрятать окна» (WF112, #8255): кого сворачивать.
/// Слово Элвиса 30.09: «мы столько окон клауд открываем, что они у меня видимые все… может, их
/// лучше скрытыми держать… показывать по слову». Свёрнутое окно Chromium не рисует
/// (`document.visibilityState = hidden`, спайк оркестратора), и M4 не греется. AX — в контроллере.
enum WindowHide {
    /// Окно Claude на экране глазами «спрятать»: главное ли и во весь экран ли.
    struct Seen: Equatable {
        let title: String
        /// `isMainWindowTitle(title) || isMainFrame(frame)` — главным зовём и по заголовку, и по
        /// рамке его страницы (правка критика WF111): резолвер заголовка может промолчать.
        let isMain: Bool
        /// `AXFullScreen`: такое окно сворачивать нельзя (macOS сперва выводит его из полного
        /// экрана), его не трогаем и считаем в `skipped`.
        let fullScreen: Bool
        /// Окно главного проекта (`mainProject` в claude.json, гейт WF111): там Рик — не сворачиваем никогда,
        /// как главное; но и главным для отказа `window-missing` оно не считается.
        var keep: Bool = false
        /// При mainProject без установленной папки сворачивать окно небезопасно.
        var projectKnown: Bool = true
    }

    enum Plan: Equatable {
        case refuse(WindowHideResult.Failure)
        /// Номера окон в списке `Seen`, которые свернуть, и сколько полноэкранных пропустили.
        case hide([Int], skipped: Int)
    }

    /// Кого сворачивать. Окон нет вовсе (ни на экране, ни свёрнутых) — `no-windows`; на экране
    /// нет главного, а спрятать есть кого — `window-missing` и ничего не трогаем (свернули бы Рика);
    /// все «главные» (их бывает два: безымянный попап носит ту же заглушку) остаются видимыми.
    static func plan(_ windows: [Seen], minimized: Int) -> Plan {
        guard !windows.isEmpty || minimized > 0 else { return .refuse(.noWindows) }
        guard windows.allSatisfy({ $0.isMain || $0.fullScreen || $0.projectKnown }) else {
            return .refuse(.windowMissing)
        }
        let others = windows.indices.filter { !windows[$0].isMain && !windows[$0].keep }
        let hide = others.filter { !windows[$0].fullScreen }
        let skipped = others.count - hide.count
        guard hide.isEmpty || windows.contains(where: { $0.isMain }) else { return .refuse(.windowMissing) }
        return .hide(hide, skipped: skipped)
    }

    /// Спрятанное и тянущее фокус (#8255): развёрнутые окна встают поверх — фокус возвращается
    /// главному окну, когда кончится анимация разворота.
    static let focusDelay: TimeInterval = 0.6

    /// Какое из спрятанных окон развернуть само (#8282: «окно, где ждут Элвиса, должно быть видно»):
    /// первое, чья страница говорит «чат ждёт тебя» (`ChatPage.waiting`). Окно ищется, как в карте чатов:
    /// попап с тем же заголовком, однофамильцы — по рамке (`ChatProbe.nearest`). nil — никто не ждёт.
    static func waiting(_ hidden: [(title: String, frame: CGRect?)], pages: [ChatPage],
                        resolve: ((String, CGRect?) -> WindowIdentity)? = nil) -> Int? {
        hidden.indices.first { page(for: hidden[$0], in: pages, resolve: resolve)?.waiting == true }
    }

    /// Страница окна по заголовку и рамке; не нашлась или однофамильцы без рамки — nil.
    static func page(for window: (title: String, frame: CGRect?), in pages: [ChatPage],
                     resolve: ((String, CGRect?) -> WindowIdentity)? = nil) -> ChatPage? {
        if let resolve = resolve {
            guard let page = resolve(window.title, window.frame).page, page.kind == .popout else { return nil }
            return page
        }
        let wanted = ChatProbe.clean(window.title)
        guard !wanted.isEmpty else { return nil }
        return ChatProbe.nearest(pages.filter { $0.kind == .popout && ChatProbe.clean($0.title) == wanted },
                                 to: window.frame)
    }
}

/// Окна, которые свернул сам Пимп (гейт 1 WF111): по ним и только по ним замерзают снимок К5 и
/// раскладка мониторов, их число — на кнопке «👀 Показать окна (N)». Окно, свёрнутое Элвисом
/// руками, сюда не попадает — иначе снимки замёрзли бы навсегда. `isMinimized` — AX: nil у
/// закрытого окна; развёрнутые и закрытые выкидываются при каждом счёте.
final class HiddenWindows<Window> {
    private var windows: [Window] = []
    private let isMinimized: (Window) -> Bool?

    init(isMinimized: @escaping (Window) -> Bool?) {
        self.isMinimized = isMinimized
    }

    func add(_ hidden: [Window]) { windows += hidden }

    func clear() { windows = [] }

    /// Спрятанные Пимпом и ещё свёрнутые, в порядке, как прятали (#8282).
    var current: [Window] {
        _ = count
        return windows
    }

    /// Окно развернул разворот «ждёт Элвиса» (#8282) — из счёта спрятанных вон.
    func remove(where gone: (Window) -> Bool) { windows.removeAll(where: gone) }

    /// Сколько спрятанных Пимпом ещё свёрнуто; пустой список — 0 без единого вызова AX.
    var count: Int {
        guard !windows.isEmpty else { return 0 }
        windows = windows.filter { isMinimized($0) == true }
        return windows.count
    }
}
