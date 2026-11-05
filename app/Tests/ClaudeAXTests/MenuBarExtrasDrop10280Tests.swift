import XCTest
@testable import ClaudeAX

/// #10280: значок из ряда «Не влезли» отпустили — куда его ⌘-перетащить в строке меню.
final class MenuBarExtrasDrop10280Tests: XCTestCase {
    private let bar = MenuBarExtras.Bar(notch: 562...718, height: 37, width: 1280)
    /// Видимые значки правее выреза: 760…1000; один под вырезом — не в счёт.
    private let shown = [CGRect(x: 760, y: 0, width: 30, height: 37), CGRect(x: 900, y: 0, width: 100, height: 37),
                         CGRect(x: 600, y: 0, width: 30, height: 37)]

    func testDropOnIconsLandsOnBarLine() {
        XCTAssertEqual(MenuBarExtras.dropPoint(CGPoint(x: 820, y: 30), bar: bar, shown: shown), CGPoint(x: 820, y: 19))
        XCTAssertEqual(MenuBarExtras.dropPoint(CGPoint(x: 820, y: 44), bar: bar, shown: shown), CGPoint(x: 820, y: 19),
                       "чуть ниже строки — всё равно в строку")
    }

    func testJustLeftOfIconsSnapsToFirst() {
        XCTAssertEqual(MenuBarExtras.dropPoint(CGPoint(x: 755, y: 10), bar: bar, shown: shown), CGPoint(x: 761, y: 19))
    }

    func testNowhereToDrop() {
        XCTAssertNil(MenuBarExtras.dropPoint(CGPoint(x: 820, y: 60), bar: bar, shown: shown), "ниже строки меню")
        XCTAssertNil(MenuBarExtras.dropPoint(CGPoint(x: 650, y: 10), bar: bar, shown: shown), "в вырезе")
        XCTAssertNil(MenuBarExtras.dropPoint(CGPoint(x: 300, y: 10), bar: bar, shown: shown), "меню программ слева")
        XCTAssertNil(MenuBarExtras.dropPoint(CGPoint(x: 1100, y: 10), bar: bar, shown: shown), "правее всех значков")
        XCTAssertNil(MenuBarExtras.dropPoint(CGPoint(x: 820, y: 10), bar: bar, shown: []), "видимых значков нет")
    }

    func testNoNotch() {
        let plain = MenuBarExtras.Bar(notch: nil, height: 24, width: 1440)
        XCTAssertEqual(MenuBarExtras.dropPoint(CGPoint(x: 620, y: 5), bar: plain, shown: [CGRect(x: 600, y: 0, width: 40, height: 24)]),
                       CGPoint(x: 620, y: 12))
    }

    /// Замер 19.10 (macOS 26): окна значков — у «Пункта управления», рамка окна не равна рамке AX.
    func testWindowByAXMiddleOnBarLayer() {
        let windows: [(id: CGWindowID, layer: Int, frame: CGRect)] = [
            (2686, 25, CGRect(x: 250, y: 744, width: 36, height: 30)),   // окно Диктатора не в строке
            (9110, 25, CGRect(x: 562, y: 0, width: 156, height: 28)),    // окно записи Диктатора над вырезом
            (2622, 25, CGRect(x: 581, y: 0, width: 36, height: 29)),
            (2646, 25, CGRect(x: 617, y: 0, width: 38, height: 29)),
            (70, 25, CGRect(x: 655, y: 0, width: 29, height: 29)),
            (3442, 0, CGRect(x: 0, y: 0, width: 1280, height: 29)),      // строка меню программы
        ]
        XCTAssertEqual(MenuBarExtras.windowID(for: CGRect(x: 557, y: 2, width: 53, height: 24), in: windows), 2622, "Диктатор")
        XCTAssertEqual(MenuBarExtras.windowID(for: CGRect(x: 624, y: 2, width: 24, height: 24), in: windows), 2646, "Gemini")
        XCTAssertEqual(MenuBarExtras.windowID(for: CGRect(x: 654, y: 2, width: 31, height: 24), in: windows), 70, "Karabiner")
        XCTAssertNil(MenuBarExtras.windowID(for: CGRect(x: 7, y: 831, width: 24, height: 24), in: windows), "убранный значок")
    }

    /// #10285: убранный значок (рамка посреди экрана) не переносится вовсе — ни одного события.
    func testOnlyNotchItemsMove() {
        let off = MenuBarExtras.Item(pid: 1, bundleId: nil, appName: "Hammerspoon", title: "", frame: CGRect(x: 7, y: 831, width: 24, height: 24), reason: .off)
        let notch = MenuBarExtras.Item(pid: 1, bundleId: nil, appName: "Dictator", title: "", frame: CGRect(x: 557, y: 2, width: 53, height: 24), reason: .notch)
        XCTAssertFalse(MenuBarExtras.movable(off))
        XCTAssertTrue(MenuBarExtras.movable(notch))
        let done = expectation(description: "отказ")
        MenuBarExtras.move(off, to: CGPoint(x: 820, y: 14)) { ok in XCTAssertFalse(ok); done.fulfill() }
        wait(for: [done], timeout: 3)
    }
}
