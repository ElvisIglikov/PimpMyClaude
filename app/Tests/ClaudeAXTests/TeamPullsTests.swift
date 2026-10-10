import AppKit
import XCTest
@testable import ClaudeAX

final class TeamPullsTests: XCTestCase {
    private func node(_ number: Int = 7, repo: String = "elvis/app") -> [String: Any] {
        ["number": number, "title": "Window fix", "createdAt": "2026-10-03T01:00:00Z", "isDraft": false,
         "state": "OPEN", "baseRefName": "main", "headRefName": "fix", "mergeable": "UNKNOWN",
         "headRefOid": "abc123", "url": "https://github.com/\(repo)/pull/\(number)",
         "author": ["login": "user-a"], "repository": ["nameWithOwner": repo],
         "commits": ["nodes": [["commit": ["statusCheckRollup": ["state": "SUCCESS"]]]]]]
    }
    private func json(_ value: Any) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: value), encoding: .utf8)!
    }
    private func page(_ nodes: [[String: Any]], count: Int? = nil, more: Bool = false,
                      cursor: String? = nil) -> String {
        json(["data": ["search": ["nodes": nodes, "issueCount": count ?? nodes.count,
                               "pageInfo": ["hasNextPage": more, "endCursor": cursor as Any? ?? NSNull()]]]])
    }
    private func ok(_ text: String) -> TeamPulls.Run { .done(status: 0, out: text, err: "") }
    private func model(_ runner: @escaping TeamPulls.Runner, now: @escaping () -> Date = Date.init,
                       background: @escaping (@escaping () -> Void) -> Void = { $0() },
                       main: @escaping (@escaping () -> Void) -> Void = { $0() }) -> TeamPulls {
        TeamPulls(runner: runner, now: now, background: background, main: main)
    }
    func testReadOnlyPaginationFiftyOneRequestsAndOrganizations() {
        var calls: [[String]] = []
        let pulls = model { args, _ in
            calls.append(args)
            XCTAssertEqual(args.first, "api")
            if args[1] == "user" { return self.ok("elvis\n") }
            if args[1] == "user/orgs?per_page=100&page=1" {
                return self.ok(self.json((0..<100).map { ["login": "org\($0)"] }))
            }
            if args[1] == "user/orgs?per_page=100&page=2" { return self.ok("[]") }
            XCTAssertEqual(args[1], "graphql")
            XCTAssertTrue(args.contains { $0.contains("org:org99") })
            if args.contains("cursor=next") { return self.ok(self.page([self.node(51, repo: "org99/app")], count: 51)) }
            return self.ok(self.page((1...50).map { self.node($0) }, count: 51, more: true, cursor: "next"))
        }
        pulls.refresh()
        XCTAssertFalse(pulls.loading)
        XCTAssertNil(pulls.error)
        XCTAssertEqual(pulls.pulls?.count, 51)
        XCTAssertEqual(calls.count, 5)
        let last = pulls.pulls?.first { $0.number == 51 }
        XCTAssertEqual(last?.headRefName, "fix")
        XCTAssertEqual(last?.state, "OPEN")
        XCTAssertEqual(last?.head, "abc123")
        XCTAssertEqual(last.flatMap(TeamPulls.link)?.absoluteString, "https://github.com/org99/app/pull/51")
    }
    func testCacheForceErrorKeepsOldListAndRetries() {
        var at = Date(timeIntervalSince1970: 1000), calls = 0, broken = false
        let pulls = model({ args, _ in
            calls += 1
            if broken { return .timedOut }
            if args[1] == "user" { return self.ok("elvis") }
            if args[1].hasPrefix("user/orgs") { return self.ok("[]") }
            return self.ok(self.page([self.node()]))
        }, now: { at })
        pulls.refresh(); XCTAssertEqual(calls, 3)
        at = at.addingTimeInterval(299)
        pulls.refresh(); XCTAssertEqual(calls, 3)
        broken = true
        pulls.refresh(force: true)
        XCTAssertEqual(pulls.pulls?.count, 1); XCTAssertEqual(pulls.error, TeamPulls.offline)
        XCTAssertFalse(pulls.loading)
        broken = false
        pulls.refresh(); XCTAssertEqual(calls, 7); XCTAssertNil(pulls.error)
        at = at.addingTimeInterval(301)
        pulls.refresh(); XCTAssertEqual(calls, 10)
    }
    func testLoadingRunsOutsideMainAndFinishesOnMain() {
        var background: (() -> Void)?, main: (() -> Void)?
        let pulls = model({ _, _ in .missing }, background: { background = $0 }, main: { main = $0 })
        pulls.refresh(); XCTAssertTrue(pulls.loading); XCTAssertNil(pulls.error)
        background?(); XCTAssertTrue(pulls.loading)
        main?(); XCTAssertFalse(pulls.loading); XCTAssertEqual(pulls.error, TeamPulls.noGh)
    }
    func testErrorsAreNeverAnEmptySuccessfulList() {
        let cases: [TeamPulls.Run] = [.missing, .timedOut,
            .done(status: 1, out: "", err: "HTTP 401: Bad credentials"),
            .done(status: 1, out: "", err: "network is unreachable")]
        for failure in cases {
            let pulls = model { _, _ in failure }
            pulls.refresh()
            XCTAssertNil(pulls.pulls); XCTAssertNotNil(pulls.error); XCTAssertFalse(pulls.loading)
        }
        for response in ["broken", "{}", "[]", "{\"data\":null,\"errors\":[{\"message\":\"oops\"}]}",
                         page([], count: 1), page([node()], count: 1001), page([], count: 0, more: true)] {
            let pulls = model { args, _ in
                if args[1] == "user" { return self.ok("elvis") }
                if args[1].hasPrefix("user/orgs") { return self.ok("[]") }
                return self.ok(response)
            }
            pulls.refresh()
            XCTAssertNil(pulls.pulls, response); XCTAssertNotNil(pulls.error, response)
        }
    }
    func testOrganizationFailureDoesNotSilentlySearchOnlyLogin() {
        var calls = 0
        let pulls = model { args, _ in
            calls += 1
            return args[1] == "user" ? self.ok("elvis") : .done(status: 1, out: "", err: "HTTP 403")
        }
        pulls.refresh()
        XCTAssertEqual(calls, 2); XCTAssertNil(pulls.pulls)
        XCTAssertTrue(pulls.error?.contains("неполный") == true)
    }
    func testEmptyCompleteListAndMalformedNodes() {
        let pulls = model { args, _ in
            if args[1] == "user" { return self.ok("elvis") }
            if args[1].hasPrefix("user/orgs") { return self.ok("[]") }
            return self.ok(self.page([]))
        }
        pulls.refresh(); XCTAssertEqual(pulls.pulls, []); XCTAssertNil(pulls.error)
        for (key, value) in [("number", true as Any), ("number", 0), ("number", 1.5), ("isDraft", 1),
                             ("url", "https://example.com/elvis/app/pull/7"), ("title", NSNull()),
                             ("commits", ["nodes": [["commit": [:]]]])] {
            var bad = node(); bad[key] = value
            XCTAssertNil(TeamPulls.parsePage(Data(page([bad]).utf8)), key)
        }
    }
    func testMissingCommitOrNullCheckStateIsIncomplete() {
        let cases: [[String: Any]] = [["nodes": []],
            ["nodes": [["commit": ["statusCheckRollup": ["state": NSNull()]]]]]]
        for commits in cases {
            var bad = node(); bad["commits"] = commits
            XCTAssertNil(TeamPulls.parsePage(Data(page([bad]).utf8)))
        }
    }
    func testDraftRedUnknownChecksAndStrictLinks() throws {
        var value = node(); value["isDraft"] = true; value["mergeable"] = "CONFLICTING"
        value["commits"] = ["nodes": [["commit": ["statusCheckRollup": ["state": "FAILURE"]]]]]
        let pull = try XCTUnwrap(TeamPulls.parsePage(Data(page([value]).utf8))?.pulls.first)
        let detail = TeamPulls.detail(pull, now: pull.created)
        XCTAssertTrue(detail.contains("черновик")); XCTAssertTrue(detail.contains("конфликт"))
        XCTAssertTrue(detail.contains("проверки ✗")); XCTAssertEqual(TeamPulls.checksWord("NEW"), "проверки неизвестны")
        XCTAssertEqual(TeamPulls.checksWord(nil), "без проверок")
        for url in ["http://github.com/elvis/app/pull/7", "https://github.com.evil/elvis/app/pull/7",
                    "https://user@github.com/elvis/app/pull/7", "https://github.com:443/elvis/app/pull/7",
                    "https://github.com/elvis/app/pull/8", "https://github.com/other/app/pull/7",
                    "https://github.com/elvis/app/pull/7?x=1", "file:///tmp/test",
                    "https://github.com/elvis/app/pull/7#fragment", "https://github.com/elvis%2fapp/pull/7"] {
            XCTAssertNil(TeamPulls.validURL(url, repo: "elvis/app", number: 7), url)
        }
        XCTAssertNotNil(TeamPulls.link(pull))
    }

    /// Same K-B4 example as pimp_prs_test.py: own author excluded, deleted author is ghost,
    /// nullable checks, draft/conflict and the exact GitHub URL all survive the Swift parser.
    func testSharedCLIContractExample() throws {
        var own = node(8, repo: "ElvisIglikov/PimpMyClaude")
        own["author"] = ["login": "elvisiglikov"]
        var ghost = node(9, repo: "VkusnoffKz/bot")
        ghost["author"] = NSNull(); ghost["title"] = " "
        ghost["commits"] = ["nodes": [["commit": ["statusCheckRollup": NSNull()]]]]
        var team = node(7, repo: "VkusnoffKz/site")
        team["author"] = ["login": "user-b"]; team["title"] = "Новое меню"
        team["isDraft"] = true; team["mergeable"] = "CONFLICTING"
        team["commits"] = ["nodes": [["commit": ["statusCheckRollup": ["state": "FAILURE"]]]]]
        let pulls = model { args, _ in
            if args[1] == "user" { return self.ok("ElvisIglikov") }
            if args[1].hasPrefix("user/orgs") { return self.ok(self.json([["login": "VkusnoffKz"]])) }
            XCTAssertTrue(args.contains("q=is:pr is:open -author:ElvisIglikov user:ElvisIglikov org:VkusnoffKz"))
            return self.ok(self.page([own, ghost, team]))
        }
        pulls.refresh()
        XCTAssertNil(pulls.error); XCTAssertEqual(pulls.pulls?.count, 2)
        let deleted = try XCTUnwrap(pulls.pulls?.first { $0.number == 9 })
        XCTAssertEqual(deleted.author, "ghost"); XCTAssertNil(deleted.checks)
        let draft = try XCTUnwrap(pulls.pulls?.first { $0.number == 7 })
        XCTAssertEqual(draft.author, "user-b"); XCTAssertEqual(draft.title, "Новое меню")
        XCTAssertTrue(draft.draft); XCTAssertEqual(draft.mergeable, "CONFLICTING")
        XCTAssertEqual(draft.checks, "FAILURE")
        XCTAssertEqual(TeamPulls.link(draft)?.absoluteString, "https://github.com/VkusnoffKz/site/pull/7")
    }

    private func executable(_ script: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wf120-gh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("fake-gh")
        try Data(("#!/bin/sh\n" + script).utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        return file
    }
    func testRealRunnerDeadlineIncludesExitAfterEOFAndKillsIgnoringTerm() throws {
        for ignore in [false, true] {
            // pid отдаёт сам run сразу после запуска — не ждём, успеет ли sh записать его в файл (WF208).
            let file = try executable((ignore ? "trap '' TERM\n" : "") + "exec 1>&- 2>&-\nwhile :; do :; done\n")
            var pid: pid_t = 0
            let start = ProcessInfo.processInfo.systemUptime
            let result = TeamPulls.run(executable: file, arguments: [], timeout: 2) { pid = $0 }
            XCTAssertEqual(result, .timedOut)
            XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 4)
            XCTAssertGreaterThan(pid, 0)
            let alive = kill(pid, 0), reason = errno
            XCTAssertEqual(alive, -1, "only our child must be gone")
            XCTAssertEqual(reason, ESRCH)
        }
    }
    func testRealRunnerDrainsLargeOutputAndNonzeroError() throws {
        let file = try executable("/usr/bin/awk 'BEGIN { for(i=0;i<50000;i++) print \"01234567890123456789\" }'\nprintf 'problem' >&2\nexit 3\n")
        let result = TeamPulls.run(executable: file, arguments: [], timeout: 60)
        guard case .done(let status, let out, let err) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(status, 3); XCTAssertEqual(out.utf8.count, 1_050_000); XCTAssertEqual(err, "problem")
    }
}
