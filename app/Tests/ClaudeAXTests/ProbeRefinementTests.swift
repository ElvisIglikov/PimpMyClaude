import XCTest
@testable import ClaudeAX

final class ProbeRefinementTests: XCTestCase {
    func testUnchangedIdentityCooldownSurvivesChannelOffAndExplicitDemandBypassesIt() throws {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        var script: String?
        var result: Data?
        var writes = 0
        var version = 0
        let files = ChatProbeFiles(scriptInfo: { script == nil ? nil : ("\(writes)", now) },
            readScript: { script }, writeScript: { script = $0; writes += 1; return true },
            resultInfo: { result == nil ? nil : "\(version)" }, readResult: { result })
        let probe = ChatProbe(files: files, now: { now })
        probe.isEnabled = { false }
        let frame = CGRect(x: 0, y: 40, width: 400, height: 700)
        let native = [WindowIdentity.Native(title: "A", frame: frame, id: 101)]
        func tick() { probe.tick(windows: [("A", frame)], indexRevision: 1) }
        func answer() throws {
            let nonce = try XCTUnwrap(script?.split(separator: "\n").first?.split(separator: " ").last.map(String.init))
            var entry = ProbeSourceFixture.entry(["id": 1, "url": "about:blank", "result": [
                "v": 1, "nonce": nonce, "kind": "popout", "self": "local_a", "title": "A", "store": "ok",
                "frame": [0, 40, 400, 700]]])
            var source = try XCTUnwrap(entry["source"] as? [String: Any]); source["windowId"] = 101; entry["source"] = source
            result = try JSONSerialization.data(withJSONObject: ["results": [entry]])
            version += 1
        }
        probe.demand(at: now); tick(); try answer()
        now += 2; tick()
        XCTAssertEqual(probe.pages.count, 1)
        // Start the automatic cooldown after the semantic page facts are known.
        probe.demandIdentity(native: native, at: now); tick(); try answer()
        now += 2; tick()
        let before = writes
        now += 31; tick()
        XCTAssertTrue(probe.pages.isEmpty)
        probe.demandIdentity(native: native, at: now); tick()
        XCTAssertEqual(writes, before, "Channel off must not turn retained facts into a new fingerprint")
        probe.demand(at: now); tick()
        XCTAssertEqual(writes, before + 1, "Explicit user demand remains immediate")
        try answer(); now += 2; tick()
        probe.demandIdentity(native: native, at: now); tick()
        XCTAssertEqual(writes, before + 1, "Fresh answer time alone does not reset the cooldown")
        probe.demandIdentity(native: [WindowIdentity.Native(title: "A", frame: frame.offsetBy(dx: 80, dy: 0), id: 101)], at: now)
        tick()
        XCTAssertEqual(writes, before + 2, "A changed native identity/geometry still gets its bounded refinement")
    }

    func testFingerprintChangesForIdentityOrGeometryButNotFreshnessOrOrdering() {
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        var a = ChatPage(kind: .popout, chat: "local_a", title: "A", store: "ok", windowId: 101, at: at)
        let b = ChatPage(kind: .main, chat: "local_b", title: "B", store: "ok", windowId: 102, at: at)
        let n = [WindowIdentity.Native(title: "A", frame: .zero, id: 101)]
        let original = ChatProbe.refinementFingerprint(native: n, pages: [a, b])
        a = ChatPage(kind: .popout, chat: "local_a", title: "A", store: "ok", windowId: 101, at: at.addingTimeInterval(30))
        XCTAssertEqual(original, ChatProbe.refinementFingerprint(native: n, pages: [b, a]))
        a = ChatPage(kind: .popout, chat: "local_c", title: "A", store: "ok", windowId: 101, at: at)
        XCTAssertNotEqual(original, ChatProbe.refinementFingerprint(native: n, pages: [a, b]))
    }
}
