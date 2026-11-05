import XCTest
@testable import ClaudeAX

/// #10252: метка в значке, когда у Claude слетели доступы macOS.
final class ClaudeAccess10252Tests: XCTestCase {
    private let anthropic = Data([1]), adhoc = Data([2])

    /// Замер 19.10: диск выдан под cdhash этой сборки, «Универсальный доступ» — под подписью Anthropic.
    func testMismatchedSignatureIsMissing() {
        let records = [ClaudeAccess.Record(service: .fullDisk, allowed: true, csreq: adhoc),
                       ClaudeAccess.Record(service: .accessibility, allowed: true, csreq: anthropic)]
        XCTAssertEqual(ClaudeAccess.evaluate(records) { $0 == self.adhoc }, .missing([.accessibility]))
        XCTAssertEqual(ClaudeAccess.evaluate(records) { _ in true }, .ok)
    }

    func testDeniedIsMissingNeverGivenIsNot() {
        let records = [ClaudeAccess.Record(service: .fullDisk, allowed: false, csreq: adhoc)]
        XCTAssertEqual(ClaudeAccess.evaluate(records) { _ in true }, .missing([.fullDisk]))
        XCTAssertEqual(ClaudeAccess.evaluate([]) { _ in false }, .ok, "ни разу не дававшееся не просим")
    }

    func testMissingDatabaseIsUnknown() {
        XCTAssertNil(ClaudeAccess.read(bundleID: "x", path: "/nonexistent/TCC.db"))
    }

    func testIconMarkAndToolTip() {
        let look = StatusIcon.look(mode: .plain, limits: nil, patch: .installed(version: "1", loader: 8),
                                   phase: .idle, now: Date(), access: ["Полный доступ к диску"])
        XCTAssertEqual(look.mark, .accessLost)
        XCTAssertTrue(look.toolTip.hasPrefix("PMP — у Claude слетели доступы: Полный доступ к диску. "))
        let lost = StatusIcon.look(mode: .plain, limits: nil, patch: .lost(version: "1"), phase: .idle, now: Date(),
                                   access: ["Полный доступ к диску"])
        XCTAssertEqual(lost.mark, .patchLost, "слетевший патч важнее")
    }
}
