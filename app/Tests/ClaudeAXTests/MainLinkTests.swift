import XCTest
@testable import ClaudeAX

/// «Открыть новый чат» из ГЛАВНОГО окна (гейт 26.09): страница claude.ai в главном окне вложена
/// в рамку `main_window`, и её `document.title` с меткой в заголовок окна не попадает — окно
/// всегда «Claude». Метку видно только в заголовке корня страницы (`AXWebArea`) внутри окна.
final class MainLinkTests: XCTestCase {
    private static let mark = "Пимп: продолжить в новом чате · mfw3k2a1"

    /// Узел дерева AX живого главного окна 2.9939.2 (снято 26.09 чтением, без кликов).
    private final class Node {
        let role: String
        let title: String
        let children: [Node]
        init(_ role: String, _ title: String = "", _ children: [Node] = []) {
            self.role = role
            self.title = title
            self.children = children
        }
    }

    /// AXWindow «Claude» → группы → две AXWebArea: рамка (пусто) на глубине 7 и claude.ai на 8.
    private func mainWindow(pageTitle: String, content: [Node] = [Node("AXGroup")]) -> Node {
        let frame = Node("AXGroup", "", [Node("AXGroup", "", [Node("AXWebArea", "", [Node("AXGroup")])])])
        let page = Node("AXGroup", "", [Node("AXGroup", "", [Node("AXWebArea", pageTitle, content)])])
        return Node("AXWindow", "Claude", [
            Node("AXGroup", "Claude", [Node("AXGroup", "", [Node("AXGroup", "", [Node("AXGroup", "", [
                Node("AXGroup", "", [frame, page]),
            ])])])]),
            Node("AXButton"), Node("AXButton", "", [Node("AXGroup")]), Node("AXButton"),
        ])
    }

    private func pageTitles(_ window: Node) -> [String] {
        ContinueWebAreas.find(root: window, children: { $0.children },
                              isWebArea: { $0.role == ContinueWebAreas.role }).map { $0.title }
    }

    func testMainWindowPagesAreFoundUnderTheFrame() {
        XCTAssertEqual(pageTitles(mainWindow(pageTitle: "Claude")), ["", "Claude"])
        XCTAssertEqual(pageTitles(mainWindow(pageTitle: MainLinkTests.mark)), ["", MainLinkTests.mark])
    }

    func testSearchDoesNotWalkIntoThePage() {
        // С включённым AX под страницей весь чат — внутрь не спускаемся, иначе опрос 0,25 с
        // обходил бы тысячи узлов.
        var visited = 0
        let chat = (0..<500).map { _ in Node("AXGroup", "", [Node("AXWebArea", "чужая")]) }
        let found = ContinueWebAreas.find(root: mainWindow(pageTitle: "Claude", content: chat),
                                          children: { visited += 1; return $0.children },
                                          isWebArea: { $0.role == ContinueWebAreas.role })
        XCTAssertEqual(found.map { $0.title }, ["", "Claude"])
        XCTAssertLessThan(visited, 20)
    }

    func testWindowTitleThenDistinctPageTitles() {
        XCTAssertEqual(ContinueWebAreas.titles(window: "Claude", pages: ["", "Claude"]), ["Claude"])
        XCTAssertEqual(ContinueWebAreas.titles(window: "Claude", pages: ["", MainLinkTests.mark]),
                       ["Claude", MainLinkTests.mark])
        // Попап: заголовок страницы и есть заголовок окна — лишней строки нет.
        XCTAssertEqual(ContinueWebAreas.titles(window: MainLinkTests.mark, pages: [MainLinkTests.mark]),
                       [MainLinkTests.mark])
    }

    /// Причина гейта целиком: по одним заголовкам окон клик в главном окне не виден, с
    /// заголовками страниц — машина запоминает ГЛАВНОЕ окно и зовёт «Новый чат», когда метка ушла.
    func testMarkInMainWindowPageFiresForTheMainWindow() {
        let popup = "Dictator марафон 2026-09-25"
        func entries(page: String) -> [(window: String, title: String)] {
            [(window: popup, title: popup)]
                + ContinueWebAreas.titles(window: "Claude", pages: ["", page]).map { (window: "Claude", title: $0) }
        }

        var blind = ContinueWatchMachine()
        XCTAssertEqual(blind.step(titles: [popup, "Claude"], now: 0), .none, "так было: метки не видно")

        var machine = ContinueWatchMachine()
        let marked = entries(page: MainLinkTests.mark)
        guard case .arm(let index) = machine.step(titles: marked.map { $0.title }, now: 0) else {
            return XCTFail("метку в странице главного окна не увидели")
        }
        XCTAssertEqual(marked[index].window, "Claude")
        XCTAssertEqual(machine.step(titles: marked.map { $0.title }, now: 0.25), .none, "метка ещё стоит")
        XCTAssertEqual(machine.step(titles: entries(page: "Claude").map { $0.title }, now: 1.3), .fire)
        XCTAssertEqual(machine.step(titles: marked.map { $0.title }, now: 1.5), .none, "одна метка — один раз")
    }
}
