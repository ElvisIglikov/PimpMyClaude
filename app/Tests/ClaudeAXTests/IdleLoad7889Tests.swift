import CoreGraphics
import XCTest
@testable import ClaudeAX

/// Нагрузка в тишине (#7889): на тике сторожа заголовки окон для покраски и канала probe берутся из переписи
/// (`ClaudeActions.paintable`), а не новым чтением рамок всех AX-окон на каждое окно с экрана; кнопка
/// «💬 Новый чат» читает заголовки страниц только у главного окна (`ContinueWebAreas.titles(of:pages:)`).
final class IdleLoad7889Tests: XCTestCase {
    private let left = CGRect(x: 0, y: 30, width: 400, height: 700)
    private let middle = CGRect(x: 410, y: 30, width: 400, height: 700)
    private let right = CGRect(x: 820, y: 30, width: 400, height: 700)
    private let below = CGRect(x: 0, y: 740, width: 400, height: 300)

    private func shifted(_ frame: CGRect, by delta: CGFloat) -> CGRect {
        frame.offsetBy(dx: delta, dy: -delta)
    }

    // MARK: - покраска и probe: заголовки из переписи

    func testPaintableTakesCensusTitlesInArrangeOrder() {
        // Quartz отдаёт окна спереди назад, перепись — в порядке AX; итог — порядок «Расставить».
        let quartz = [ClaudeWindowFrame(id: 7, frame: right), .init(id: 3, frame: below),
                      .init(id: 5, frame: left), .init(id: 9, frame: middle)]
        let native = [WindowIdentity.Native(title: "Claude", frame: shifted(left, by: 1)),
                      .init(title: "VkusnoffKz 2", frame: below),
                      .init(title: "Trelvis", frame: shifted(middle, by: 2)),
                      .init(title: "Dictator марафон", frame: right)]
        let seen = ClaudeActions.paintable(quartz, native: native)
        XCTAssertEqual(seen.titles, ["Claude", "Trelvis", "Dictator марафон", "VkusnoffKz 2"])
        XCTAssertEqual(seen.named.map { $0.title }, seen.titles)
        XCTAssertEqual(seen.named.map { $0.frame }, [left, middle, right, below], "рамки — с экрана (Quartz), не из AX")
        XCTAssertEqual(seen.onScreen, 4)
        XCTAssertEqual(seen.shared, 0)
        XCTAssertEqual(seen.skipped, 0)
    }

    func testPaintableSkipsUnpairedUntitledAndCollapsesTwins() {
        let quartz = [ClaudeWindowFrame(id: 1, frame: left), .init(id: 2, frame: middle),
                      .init(id: 3, frame: right), .init(id: 4, frame: below)]
        let native = [WindowIdentity.Native(title: "Ожидание задачи", frame: left),
                      .init(title: "Ожидание задачи", frame: middle),
                      .init(title: "", frame: right),
                      .init(title: "Без рамки", frame: nil)]
        let seen = ClaudeActions.paintable(quartz, native: native)
        XCTAssertEqual(seen.titles, ["Ожидание задачи"], "однофамильцы схлопнуты: тема живёт на чате")
        XCTAssertEqual(seen.named.map { $0.title }, ["Ожидание задачи", "Ожидание задачи"],
                       "каналу probe — оба окна, их различает рамка")
        XCTAssertEqual(seen.named.map { $0.frame }, [left, middle])
        XCTAssertEqual(seen.onScreen, 4)
        XCTAssertEqual(seen.skipped, 2, "пустой заголовок и окно без AX-пары")
        XCTAssertEqual(seen.shared, 1)
    }

    func testFrameToleranceIsTheOldWindowMatchingRule() {
        // Прежний `ClaudeApp.window(matching:)` — допуск 2 pt по каждой стороне.
        let quartz = [ClaudeWindowFrame(id: 1, frame: left)]
        XCTAssertEqual(ClaudeActions.paintable(quartz, native: [.init(title: "A", frame: shifted(left, by: 2))]).titles, ["A"])
        let far = ClaudeActions.paintable(quartz, native: [.init(title: "A", frame: shifted(left, by: 3))])
        XCTAssertEqual(far.titles, [])
        XCTAssertEqual(far.skipped, 1)
    }

    func testTwinOnAnotherDesktopKeepsItsTitle() {
        // Находка критика: окно Claude на другом рабочем столе с той же рамкой (частое после «Расставить»
        // на нескольких столах). AX видит только окна текущего стола, перепись — все столы, и её пара
        // однозначна в обе стороны: пары нет. Прежнее правило (одно AX-окно на рамку) окно узнаёт — и мы тоже.
        let here = ClaudeWindowFrame(id: 1, frame: left)
        let otherDesk = ClaudeWindowFrame(id: 2, frame: left, onScreen: false)
        let native = [WindowIdentity.Native(title: "Trelvis", frame: left)]
        XCTAssertTrue(WindowCensus.pair(native: native, quartz: [here, otherDesk]).pairs.isEmpty,
                      "пары переписи для покраски не годятся")
        let seen = ClaudeActions.paintable([here], native: native)
        XCTAssertEqual(seen.titles, ["Trelvis"])
        XCTAssertEqual(seen.skipped, 0)
    }

    func testTwoAXWindowsOnOneFrameAreSkipped() {
        // Два окна стопкой (или свёрнутое с той же рамкой): какое из них на экране, по рамке не сказать.
        let native = [WindowIdentity.Native(title: "Trelvis", frame: left), .init(title: "VkusnoffKz 2", frame: left)]
        let seen = ClaudeActions.paintable([ClaudeWindowFrame(id: 1, frame: left)], native: native)
        XCTAssertEqual(seen.titles, [])
        XCTAssertEqual(seen.named.count, 0)
        XCTAssertEqual(seen.skipped, 1)
    }

    func testNoWindowsOnScreenGivesNothing() {
        let seen = ClaudeActions.paintable([], native: [.init(title: "Trelvis", frame: left)])
        XCTAssertEqual(seen.titles, [])
        XCTAssertEqual(seen.onScreen, 0)
        XCTAssertEqual(seen.shared, 0)
        XCTAssertEqual(seen.skipped, 0)
    }

    // MARK: - кнопка «💬 Новый чат»: страницы — только у главного окна

    func testPagesAreReadOnlyForTheMainWindow() {
        let mark = ContinueWatch.labelPrefix + " · mfw3k2a1"
        let popup = "Dictator марафон 2026-09-25"
        var read: [String] = []
        let pages: (String) -> [String] = { window in
            read.append(window)
            return window == "main" ? ["", mark] : [popup]
        }
        let windows = [(window: "popup", title: popup), (window: "main", title: "Claude"),
                       (window: "marked", title: mark)]
        let titles = ContinueWebAreas.titles(of: windows, pages: pages)
        XCTAssertEqual(read, ["main"], "у попапа заголовок страницы и есть заголовок окна — его страницы не читаем")
        XCTAssertEqual(titles.map { $0.window }, ["popup", "main", "main", "marked"])
        XCTAssertEqual(titles.map { $0.title }, [popup, "Claude", mark, mark])
    }

    func testEmptyOrStubTitleCountsAsMain() {
        // Пустой заголовок и заглушка «Claude» (её носит и безымянный попап) — страницы читаем: лишнее
        // чтение дешевле пропущенного клика.
        var read: [String] = []
        let windows = [(window: "a", title: ""), (window: "b", title: "  Claude "), (window: "c", title: "Trelvis")]
        _ = ContinueWebAreas.titles(of: windows) { window in
            read.append(window)
            return []
        }
        XCTAssertEqual(read, ["a", "b"])
    }

    func testMarkInMainWindowPageStillFiresThroughTheFork() {
        let mark = ContinueWatch.labelPrefix + " · mfw3k2a1"
        let popup = "Dictator марафон 2026-09-25"
        func poll(page: String) -> [(window: String, title: String)] {
            ContinueWebAreas.titles(of: [(window: "popup", title: popup), (window: "main", title: "Claude")]) {
                $0 == "main" ? ["", page] : []
            }
        }
        var machine = ContinueWatchMachine()
        let marked = poll(page: mark)
        guard case .arm(let index) = machine.step(titles: marked.map { $0.title }, now: 0) else {
            return XCTFail("метку в странице главного окна не увидели")
        }
        XCTAssertEqual(marked[index].window, "main")
        XCTAssertEqual(machine.step(titles: marked.map { $0.title }, now: ContinueWatch.pollInterval), .none)
        XCTAssertEqual(machine.step(titles: poll(page: "Claude").map { $0.title }, now: 1.3), .fire)
    }

    func testPopupMarkInWindowTitleStillFires() {
        let mark = ContinueWatch.labelPrefix + " · mfw3k9zz"
        var machine = ContinueWatchMachine()
        let marked = ContinueWebAreas.titles(of: [(window: "main", title: "Claude"), (window: "popup", title: mark)]) {
            _ in ["", "Claude"]
        }
        guard case .arm(let index) = machine.step(titles: marked.map { $0.title }, now: 0) else {
            return XCTFail("метку в заголовке попапа не увидели")
        }
        XCTAssertEqual(marked[index].window, "popup")
    }

    // MARK: - вода маяка: у Мака никого — кадр стоит

    func testConsentWaterFreezesWhenNobodyTouchesMac() {
        let minute = ConsentWaterOverlay.idleFreeze
        XCTAssertFalse(ConsentWaterOverlay.frozen(alive: true, idle: minute - 1, shown: 3600), "тронули мышь — вода живая")
        XCTAssertTrue(ConsentWaterOverlay.frozen(alive: true, idle: minute, shown: minute))
        XCTAssertFalse(ConsentWaterOverlay.frozen(alive: true, idle: 3600, shown: 5),
                       "запрос пришёл ночью — минуту вода живая, кадр не замирает недорисованным")
        XCTAssertFalse(ConsentWaterOverlay.frozen(alive: false, idle: 3600, shown: 3600), "ответили — стекает и гаснет")
    }
}
