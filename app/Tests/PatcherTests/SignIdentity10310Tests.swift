import XCTest
@testable import Patcher

/// #10310, контракт К-SIGN: постоянная подпись Claude — выбор личности, файл `sign-identity.json`, своя личность и
/// проба. Связка ключей и `codesign` не трогаются: утилиты подменяет `run`. Эталон выбора — общий с
/// `tests/sign-identity-10310.test.mjs` (`tests/fixtures/sign-identity`).
final class SignIdentity10310Tests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("sign-10310-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: scratch) }

    private var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("tests/fixtures/sign-identity")
    }

    /// Подставные утилиты: журнал вызовов и ответ по пути утилиты и первому аргументу.
    private final class Tools {
        var calls: [(String, [String])] = []
        var answer: (String, [String]) throws -> String = { _, _ in "" }
        func run(_ path: String, _ arguments: [String], _ timeout: TimeInterval) throws -> String {
            calls.append((path, arguments))
            return try answer(path, arguments)
        }
        func called(_ path: String, _ first: String) -> [String]? {
            calls.first { $0.0 == path && $0.1.first == first }?.1
        }
    }

    private struct Failure: Error {}

    // MARK: общий эталон

    func testSharedFixtureCases() throws {
        let data = try Data(contentsOf: fixtures.appendingPathComponent("cases.json"))
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 8)
        for item in cases {
            let name = item["name"] as? String ?? "?"
            let list = try String(contentsOf: fixtures.appendingPathComponent(try XCTUnwrap(item["list"] as? String)),
                                  encoding: .utf8)
            let parsed = SignIdentity.parse(findIdentity: list)
            XCTAssertEqual(parsed.count, item["count"] as? Int, "\(name): повторы по SHA-1 не убраны")
            let saved = (item["saved"] as? [String: String]).flatMap { json in
                json["kind"].flatMap(SignIdentity.Kind.init(rawValue:)).map { SignIdentity.Choice(sha1: json["sha1"] ?? "", kind: $0) }
            }
            let expect = (item["expect"] as? [String: String]).flatMap { json in
                json["kind"].flatMap(SignIdentity.Kind.init(rawValue:)).map { SignIdentity.Choice(sha1: json["sha1"] ?? "", kind: $0) }
            }
            XCTAssertEqual(SignIdentity.choose(parsed, saved: saved), expect, name)
        }
    }

    func testUntrustedLocalIsUsableExpiredIsNot() {
        let list = """
              1) E6282567E9AC9930B040F0368D3AB8FF783032A6 "PimpMyClaude Local Signing" (CSSMERR_TP_NOT_TRUSTED)
              2) 3333333333333333333333333333333333333333 "Developer ID Application: ELVIS IGLIKOV (F27N4S4NJ4)" (CSSMERR_TP_CERT_EXPIRED)
            """
        let parsed = SignIdentity.parse(findIdentity: list)
        XCTAssertEqual(parsed.first, SignIdentity.Candidate(sha1: "E6282567E9AC9930B040F0368D3AB8FF783032A6",
                                                            name: SignIdentity.localName, problem: "CSSMERR_TP_NOT_TRUSTED"))
        XCTAssertEqual(SignIdentity.choose(parsed, saved: nil)?.kind, .local)
        XCTAssertNil(SignIdentity.choose(SignIdentity.parse(findIdentity: ""), saved: nil), "ничего нет — временная подпись")
    }

    // MARK: sign-identity.json

    func testFileRoundTripAndForeignVersion() throws {
        let choice = SignIdentity.Choice(sha1: "E6282567E9AC9930B040F0368D3AB8FF783032A6", kind: .local)
        try SignIdentity.save(choice, to: scratch)
        XCTAssertEqual(SignIdentity.load(from: scratch), choice)
        let url = scratch.appendingPathComponent(SignIdentity.fileName)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 1)
        XCTAssertEqual(json["kind"] as? String, "local")
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        try Data(#"{"version":2,"sha1":"E6282567E9AC9930B040F0368D3AB8FF783032A6","kind":"local"}"#.utf8).write(to: url)
        XCTAssertNil(SignIdentity.load(from: scratch), "чужая версия файла — как нет файла")
        try Data(#"{"version":1,"sha1":"не-хэш","kind":"local"}"#.utf8).write(to: url)
        XCTAssertNil(SignIdentity.load(from: scratch))
        try Data(#"{"version":1,"sha1":"E6282567E9AC9930B040F0368D3AB8FF783032A6","kind":"apple"}"#.utf8).write(to: url)
        XCTAssertNil(SignIdentity.load(from: scratch))
    }

    // MARK: своя личность

    func testCreateLocalImportsForCodesignWithoutTrust() {
        let tools = Tools()
        tools.answer = { path, arguments in
            if path == "/usr/bin/security", arguments.first == "find-certificate" { throw Failure() }
            return ""
        }
        let keychain = scratch.appendingPathComponent("test.keychain-db")
        XCTAssertTrue(SignIdentity.createLocal(keychain: keychain, run: tools.run))
        let request = tools.called("/usr/bin/openssl", "req") ?? []
        XCTAssertTrue(request.contains("extendedKeyUsage=critical,codeSigning"))
        XCTAssertTrue(request.contains("/CN=" + SignIdentity.localName))
        XCTAssertEqual(request.firstIndex(of: "-days").map { request[$0 + 1] }, "3650", "10 лет")
        XCTAssertNotNil(tools.called("/usr/bin/openssl", "pkcs12"))
        let imported = tools.called("/usr/bin/security", "import") ?? []
        XCTAssertEqual(imported.firstIndex(of: "-k").map { imported[$0 + 1] }, keychain.path)
        XCTAssertEqual(imported.firstIndex(of: "-T").map { imported[$0 + 1] }, "/usr/bin/codesign")
        XCTAssertFalse(tools.calls.contains { $0.1.contains("add-trusted-cert") || $0.1.contains("set-key-partition-list") },
                       "доверие и partition list спросили бы пароль от Мака")
    }

    func testCreateLocalSkipsWhenCertificateAlreadyThere() {
        let tools = Tools()
        tools.answer = { _, arguments in
            arguments.first == "find-certificate" ? "    \"labl\"<blob>=\"PimpMyClaude Local Signing\"\n" : ""
        }
        XCTAssertFalse(SignIdentity.createLocal(keychain: scratch.appendingPathComponent("k"), run: tools.run))
        XCTAssertEqual(tools.calls.count, 1, "сертификат есть, а ключа нет — второй не заводим")
    }

    /// `security find-certificate -c` ищет по части имени: чужой «PimpMyClaude Local Signing Old» — не наш.
    func testCreateLocalIgnoresSimilarName() {
        let tools = Tools()
        tools.answer = { _, arguments in
            arguments.first == "find-certificate" ? "    \"labl\"<blob>=\"PimpMyClaude Local Signing Old\"\n" : ""
        }
        XCTAssertTrue(SignIdentity.createLocal(keychain: scratch.appendingPathComponent("k"), run: tools.run))
        XCTAssertNotNil(tools.called("/usr/bin/security", "import"))
    }

    func testCreateLocalFailureIsFalse() {
        let tools = Tools()
        tools.answer = { path, arguments in
            if arguments.first == "find-certificate" || arguments.first == "import" { throw Failure() }
            return ""
        }
        XCTAssertFalse(SignIdentity.createLocal(keychain: scratch.appendingPathComponent("k"), run: tools.run))
    }

    // MARK: проба и выбор целиком

    func testUsableNeedsQuickSecondTry() {
        var answers: [TimeInterval?] = []
        let trial: (String) -> TimeInterval? = { _ in answers.removeFirst() }
        answers = [0.1]
        XCTAssertTrue(SignIdentity.usable("X", trial: trial))
        answers = [8, 0.2]
        XCTAssertTrue(SignIdentity.usable("X", trial: trial), "окно один раз — «Всегда разрешать» нажали")
        answers = [8, 9]
        XCTAssertFalse(SignIdentity.usable("X", trial: trial), "окно каждый раз — в этот раз временная")
        answers = [nil]
        XCTAssertFalse(SignIdentity.usable("X", trial: trial))
    }

    func testResolveCreatesProbesAndRemembers() throws {
        let local = try String(contentsOf: fixtures.appendingPathComponent("local-only.txt"), encoding: .utf8)
        let tools = Tools()
        var created = false
        tools.answer = { path, arguments in
            switch (path, arguments.first) {
            case ("/usr/bin/security", "find-identity"?): return created ? local : ""
            case ("/usr/bin/security", "find-certificate"?): throw Failure()
            case ("/usr/bin/security", "import"?): created = true; return ""
            default: return ""
            }
        }
        var log: [String] = []
        let choice = SignIdentity.resolve(supportDirectory: scratch, create: true, run: tools.run) { log.append($0) }
        XCTAssertEqual(choice, SignIdentity.Choice(sha1: "E6282567E9AC9930B040F0368D3AB8FF783032A6", kind: .local))
        XCTAssertEqual(SignIdentity.load(from: scratch), choice, "выбор запомнен")
        XCTAssertTrue(log.contains(SignIdentity.passwordLine), "про окно пароля сказано до пробы")
        let probe = try XCTUnwrap(tools.called("/usr/bin/codesign", "--force"))
        XCTAssertTrue(probe.contains("E6282567E9AC9930B040F0368D3AB8FF783032A6"))
        XCTAssertTrue(tools.calls.contains { $0.0.hasSuffix("pmp-sign-probe") }, "подписанную копию запускают")

        // Второй раз: личность та же, файл уже есть — про пароль ни слова, своя не заводится.
        log = []
        tools.calls = []
        XCTAssertEqual(SignIdentity.resolve(supportDirectory: scratch, create: true, run: tools.run) { log.append($0) }, choice)
        XCTAssertFalse(log.contains(SignIdentity.passwordLine))
        XCTAssertNil(tools.called("/usr/bin/openssl", "req"))
    }

    func testResolveFailedProbeIsAdhoc() throws {
        let local = try String(contentsOf: fixtures.appendingPathComponent("local-only.txt"), encoding: .utf8)
        let tools = Tools()
        tools.answer = { path, arguments in
            if path == "/usr/bin/codesign" { throw Failure() }
            return arguments.first == "find-identity" ? local : ""
        }
        XCTAssertNil(SignIdentity.resolve(supportDirectory: scratch, create: true, run: tools.run))
        XCTAssertNil(SignIdentity.load(from: scratch), "непригодную личность не запоминаем")
    }

    func testResolveWithoutCreateDoesNotMakeIdentity() {
        let tools = Tools()
        XCTAssertNil(SignIdentity.resolve(supportDirectory: scratch, create: false, run: tools.run))
        XCTAssertNil(tools.called("/usr/bin/openssl", "req"))
    }

    /// Копия Claude в тестах (`signsApp`/`managesClaudeProcess` выключены) связку ключей не трогает.
    func testPatcherCopyNeverAsksKeychain() {
        var patcher = ClaudePatcher(appURL: scratch.appendingPathComponent("Claude.app"), supportDirectory: scratch,
                                    resourcesDirectory: nil)
        patcher.signsApp = true
        patcher.managesClaudeProcess = false
        XCTAssertFalse(patcher.livesSigning)
        XCTAssertNil(patcher.signIdentity(progress: { _ in }))
    }
}
