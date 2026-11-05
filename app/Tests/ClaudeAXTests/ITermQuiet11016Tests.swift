import Foundation
import XCTest
@testable import ClaudeAX

/// #11016, второй заход: iTerm, показавшийся без человека, Пимп прячет; показ человека — нет.
final class ITermQuiet11016Tests: XCTestCase {
    func testShownByItselfIsHidden() {
        XCTAssertTrue(ITermQuiet.shouldHide(active: false, allowed: false, sinceInput: 0.1),
                      "неактивный показался сам: человек показывает iTerm, только делая его активным")
        XCTAssertTrue(ITermQuiet.shouldHide(active: true, allowed: false, sinceInput: 30),
                      "стал активным, а человек ничего не нажимал")
    }

    func testHumanShowStays() {
        XCTAssertFalse(ITermQuiet.shouldHide(active: true, allowed: false, sinceInput: 0.3), "клик в Dock, ⌘Tab")
        XCTAssertFalse(ITermQuiet.shouldHide(active: true, allowed: true, sinceInput: 30), "строка «Терминалов»")
        XCTAssertFalse(ITermQuiet.shouldHide(active: false, allowed: true, sinceInput: 30), "pimp.py term --show")
    }

    func testLaunchCountsFromLaunch() {
        XCTAssertFalse(ITermQuiet.shouldHide(active: true, allowed: false, sinceInput: 3, sinceLaunch: 2.5),
                       "клик в Dock, iTerm запускался 2,5 с")
        XCTAssertFalse(ITermQuiet.shouldHide(active: false, allowed: false, sinceInput: 1, sinceLaunch: 0.3),
                       "запуск по клику, активным ещё не стал")
        XCTAssertTrue(ITermQuiet.shouldHide(active: true, allowed: false, sinceInput: 60, sinceLaunch: 2.5),
                      "запущен без человека (open из скрипта)")
        XCTAssertTrue(ITermQuiet.shouldHide(active: true, allowed: false, sinceInput: 5, sinceLaunch: 3600),
                      "давно запущен — окно нажатия обычное")
    }

    func testAllowWindow() throws {
        let quiet = ITermQuiet()
        let mark = FileManager.default.temporaryDirectory.appendingPathComponent("show-at-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: mark) }
        XCTAssertFalse(quiet.allowed(mark: mark), "ни строки, ни метки")
        quiet.allow()
        XCTAssertTrue(quiet.allowed(mark: mark))
        XCTAssertFalse(quiet.allowed(now: Date().addingTimeInterval(ITermQuiet.allowSeconds + 1), mark: mark))
        try Data("1\n".utf8).write(to: mark)
        let later = Date().addingTimeInterval(ITermQuiet.allowSeconds + 1)
        try FileManager.default.setAttributes([.modificationDate: later.addingTimeInterval(-2)], ofItemAtPath: mark.path)
        XCTAssertTrue(quiet.allowed(now: later, mark: mark), "свежая метка `--show`")
        try FileManager.default.setAttributes([.modificationDate: later.addingTimeInterval(-60)], ofItemAtPath: mark.path)
        XCTAssertFalse(quiet.allowed(now: later, mark: mark), "старая метка не держит")
    }
}
