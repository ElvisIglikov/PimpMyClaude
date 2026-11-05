import XCTest
@testable import ClaudeAX

/// Сторож контекста: «стоит» читается из settings.json, путь с пробелом приходит в кавычках `shlex.quote`.
final class KontekstGuardTests: XCTestCase {
    private let path = "/Users/x/Library/Application Support/MyClaude/kontekst/kontekst_storozh.py"

    private func settings(events: [String], window: Bool = true) throws -> Data {
        let group: [String: Any] = ["hooks": [["type": "command", "command": "python3 '\(path)'"]]]
        var json: [String: Any] = ["hooks": Dictionary(uniqueKeysWithValues: events.map { ($0, [group]) })]
        if window { json["autoCompactWindow"] = 283000 }
        return try JSONSerialization.data(withJSONObject: json)
    }

    func testShellWordsKeepQuotedSpace() {
        XCTAssertEqual(KontekstGuard.shellWords("python3 '\(path)'"), ["python3", path])
        XCTAssertEqual(KontekstGuard.shellWords("python3 /a/b\\ c.py"), ["python3", "/a/b c.py"])
        XCTAssertEqual(KontekstGuard.shellWords("python3 'a'\"'\"'b'"), ["python3", "a'b"])
    }

    func testInstalledNeedsAllEventsWindowAndFile() throws {
        let all = KontekstGuard.events
        XCTAssertTrue(KontekstGuard.isInstalled(settings: try settings(events: all), exists: { $0 == self.path }))
        XCTAssertFalse(KontekstGuard.isInstalled(settings: try settings(events: Array(all.dropLast())), exists: { _ in true }))
        XCTAssertFalse(KontekstGuard.isInstalled(settings: try settings(events: all, window: false), exists: { _ in true }))
        XCTAssertFalse(KontekstGuard.isInstalled(settings: try settings(events: all), exists: { _ in false }))
        XCTAssertFalse(KontekstGuard.isInstalled(settings: nil))
        XCTAssertFalse(KontekstGuard.isInstalled(settings: Data("не json".utf8)))
    }

    func testIconMarkWeakerThanAccess() {
        let patch = StatusIcon.Patch.installed(version: "1", loader: 8)
        let look = StatusIcon.look(mode: .plain, limits: nil, patch: patch, phase: .idle, now: Date(), guardMissing: true)
        XCTAssertEqual(look.mark, .guardLost)
        XCTAssertTrue(look.toolTip.hasPrefix("PMP — сторож контекста не стоит. "))
        let ready = StatusIcon.look(mode: .plain, limits: nil, patch: patch, phase: .ready(version: "2"), now: Date(),
                                    guardMissing: true)
        XCTAssertEqual(ready.mark, .guardLost, "точка сильнее треугольника")
        let access = StatusIcon.look(mode: .plain, limits: nil, patch: patch, phase: .idle, now: Date(),
                                     access: ["Полный доступ к диску"], guardMissing: true)
        XCTAssertEqual(access.mark, .accessLost, "непустой access всегда даёт accessLost")
        let lost = StatusIcon.look(mode: .plain, limits: nil, patch: .lost(version: "1"), phase: .idle, now: Date(),
                                   guardMissing: true)
        XCTAssertEqual(lost.mark, .patchLost, "слетевший патч важнее")
    }

    func testRefreshCopyOnlyOverExistingCopy() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let bundled = root.appendingPathComponent("bundled", isDirectory: true)
        let target = root.appendingPathComponent("target", isDirectory: true)
        try fm.createDirectory(at: bundled, withIntermediateDirectories: true)
        for name in [KontekstGuard.scriptName, KontekstGuard.helperName] {
            try Data("новый".utf8).write(to: bundled.appendingPathComponent(name))
        }
        KontekstGuard.refreshCopy(from: bundled, to: target)
        XCTAssertFalse(fm.fileExists(atPath: target.path), "копии нет — сторож не ставили, файлы не кладём")
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        let script = target.appendingPathComponent(KontekstGuard.scriptName)
        try Data("старый".utf8).write(to: script)
        KontekstGuard.refreshCopy(from: bundled, to: target)
        XCTAssertEqual(try Data(contentsOf: script), Data("новый".utf8))
        XCTAssertTrue(fm.fileExists(atPath: target.appendingPathComponent(KontekstGuard.helperName).path))
    }

    func testFailureSpeaksPlainly() {
        XCTAssertNil(KontekstGuard.failure(status: 0, output: "✅"))
        XCTAssertTrue(KontekstGuard.failure(status: 127, output: "")?.contains("python3") == true)
        XCTAssertEqual(KontekstGuard.failure(status: 1, output: "шаг\n⛔ не вышло\n"), "⛔ не вышло")
        XCTAssertEqual(KontekstGuard.failure(status: 3, output: ""), "установка сорвалась, нажми ещё раз")
    }
}
