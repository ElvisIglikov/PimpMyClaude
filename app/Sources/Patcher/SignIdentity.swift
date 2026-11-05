import Foundation
import Security

/// Постоянная подпись пропатченного Claude (#10310, контракт К-SIGN — `docs/contracts/495-10310-sign-identity.md`).
///
/// Зачем: macOS хранит доступ («Универсальный доступ», «Запись экрана», «Полный доступ к диску») вместе с требованием к
/// подписи. Временная (ad-hoc) подпись даёт новое требование на каждый патч — доступ слетает («доступ к прошлому
/// Claude»). Подпись личностью из связки ключей даёт требование `identifier "…" and certificate leaf = H"<SHA-1>"`:
/// от патча к патчу и после обновления Claude оно то же, и выданный доступ остаётся.
///
/// Проверено 19.10.2026 во временной связке ключей (не во «Входе»): самоподписанный сертификат без доверия
/// (`CSSMERR_TP_NOT_TRUSTED`) `codesign` берёт без окна и без `set-key-partition-list`, `--verify --deep --strict`
/// проходит, подписанная программа запускается. Во «Входе» окно всё же может быть — поэтому проба до закрытия Claude.
public enum SignIdentity {
    /// Личность Элвиса (ею собираются релизы) — только по точному имени.
    public static let developerIDName = "Developer ID Application: ELVIS IGLIKOV (F27N4S4NJ4)"
    /// Своя личность этого Мака: PMP заводит её один раз.
    public static let localName = "PimpMyClaude Local Signing"
    public static let fileName = "sign-identity.json"
    /// Шаг `codesign` с личностью не дольше: дольше — висит окно связки ключей, ставим временную.
    public static let signTimeout: TimeInterval = 120
    /// Проба дольше — macOS спрашивала доступ к ключу.
    static let quickProbe: TimeInterval = 2
    public static let passwordLine =
        "macOS может спросить пароль от Мака — введи его и нажми «Всегда разрешать», это один раз."

    public enum Kind: String {
        case developerID = "developer-id"
        case local
    }

    /// Строка `security find-identity`: SHA-1 сертификата, имя и ошибка в скобках (нет — nil).
    public struct Candidate: Equatable {
        public let sha1: String
        public let name: String
        public let problem: String?
        public init(sha1: String, name: String, problem: String?) {
            self.sha1 = sha1
            self.name = name
            self.problem = problem
        }
    }

    public struct Choice: Equatable {
        public let sha1: String
        public let kind: Kind
        public init(sha1: String, kind: Kind) {
            self.sha1 = sha1
            self.kind = kind
        }
    }

    /// Запуск утилиты: путь, аргументы, срок. Тесты подменяют.
    public typealias Run = (String, [String], TimeInterval) throws -> String
    public static let shell: Run = { try Shell.run($0, $1, timeout: $2) }

    // MARK: выбор — чистые функции (тот же выбор у `patch-claude.mjs`, общий эталон `tests/fixtures/sign-identity`)

    private static let line = try! NSRegularExpression(
        pattern: #"^\s*\d+\)\s+([0-9A-Fa-f]{40})\s+"(.*)"(?:\s+\((.*)\))?\s*$"#)

    /// Вывод `security find-identity -p codesigning` БЕЗ `-v`: так видна и своя личность без доверия. Раздел
    /// «Valid identities only» повторяет строки — повторы по SHA-1 убираются.
    public static func parse(findIdentity text: String) -> [Candidate] {
        var out: [Candidate] = []
        var seen = Set<String>()
        for raw in text.components(separatedBy: "\n") {
            let range = NSRange(raw.startIndex..., in: raw)
            guard let match = line.firstMatch(in: raw, range: range),
                  let shaRange = Range(match.range(at: 1), in: raw),
                  let nameRange = Range(match.range(at: 2), in: raw) else { continue }
            let sha1 = raw[shaRange].uppercased()
            guard seen.insert(sha1).inserted else { continue }
            let problem = Range(match.range(at: 3), in: raw).map { String(raw[$0]) }
            out.append(Candidate(sha1: sha1, name: String(raw[nameRange]), problem: problem?.isEmpty == true ? nil : problem))
        }
        return out
    }

    /// Чем годится личность: Developer ID — только без ошибок; своя — и без доверия; просроченная, отозванная и
    /// чужая — ничем.
    static func kind(of candidate: Candidate) -> Kind? {
        if candidate.name == developerIDName { return candidate.problem == nil ? .developerID : nil }
        guard candidate.name == localName else { return nil }
        guard let problem = candidate.problem else { return .local }
        return problem.contains("NOT_TRUSTED") ? .local : nil
    }

    /// Сохранённая личность ещё годится — она (подпись не должна меняться); иначе Developer ID, иначе своя, иначе nil
    /// (подпись будет временной).
    public static func choose(_ candidates: [Candidate], saved: Choice?) -> Choice? {
        let usable = candidates.compactMap { candidate in kind(of: candidate).map { Choice(sha1: candidate.sha1, kind: $0) } }
        if let saved = saved, let same = usable.first(where: { $0.sha1 == saved.sha1.uppercased() }) { return same }
        return usable.first { $0.kind == .developerID } ?? usable.first { $0.kind == .local }
    }

    // MARK: файл `sign-identity.json` (пишет только приложение; `patch-claude.mjs` читает)

    public static func load(from directory: URL) -> Choice? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (json["version"] as? Int) == 1,
              let sha1 = json["sha1"] as? String, isSHA1(sha1),
              let kind = (json["kind"] as? String).flatMap(Kind.init(rawValue:)) else { return nil }
        return Choice(sha1: sha1.uppercased(), kind: kind)
    }

    public static func save(_ choice: Choice, to directory: URL) throws {
        let json: [String: Any] = ["version": 1, "sha1": choice.sha1, "kind": choice.kind.rawValue]
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try SupportFiles.write(data + Data("\n".utf8), to: directory.appendingPathComponent(fileName))
    }

    static func isSHA1(_ text: String) -> Bool {
        text.count == 40 && text.allSatisfy { $0.isHexDigit }
    }

    // MARK: своя личность

    public static var loginKeychain: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Keychains/login.keychain-db")
    }

    /// Завести «PimpMyClaude Local Signing» один раз: самоподписанный сертификат для подписи кода на 10 лет и импорт в
    /// `keychain` с доступом для `/usr/bin/codesign`. Доверие не ставится и `set-key-partition-list` не зовётся — оба
    /// спросили бы пароль от Мака. Сертификат с этим именем уже есть, а личности нет — второй не заводится.
    @discardableResult
    public static func createLocal(keychain: URL = loginKeychain, run: Run = shell,
                                   progress: (String) -> Void = { _ in }) -> Bool {
        // `-c` ищет по части имени — сверяем метку целиком.
        let found = (try? run("/usr/bin/security", ["find-certificate", "-a", "-c", localName, keychain.path], 30)) ?? ""
        if found.contains("\"labl\"<blob>=\"\(localName)\"") {
            progress("Сертификат «\(localName)» в связке ключей есть, а ключа к нему нет — подпись будет временной.")
            return false
        }
        guard let folder = privateFolder() else { return false }
        defer { try? FileManager.default.removeItem(at: folder) }
        let key = folder.appendingPathComponent("key.pem").path
        let cert = folder.appendingPathComponent("cert.pem").path
        let p12 = folder.appendingPathComponent("id.p12").path
        let password = randomHex()
        do {
            // Строго системный LibreSSL: `.p12` от OpenSSL 3 из Homebrew `security import` не принимает.
            _ = try run("/usr/bin/openssl", ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert,
                                         "-days", "3650", "-subj", "/CN=" + localName,
                                         "-addext", "extendedKeyUsage=critical,codeSigning",
                                         "-addext", "keyUsage=critical,digitalSignature",
                                         "-addext", "basicConstraints=critical,CA:false"], 60)
            _ = try run("/usr/bin/openssl", ["pkcs12", "-export", "-inkey", key, "-in", cert, "-out", p12,
                                         "-passout", "pass:" + password, "-name", localName], 60)
            _ = try run("/usr/bin/security", ["import", p12, "-k", keychain.path, "-f", "pkcs12", "-P", password,
                                          "-T", "/usr/bin/codesign"], 120)
        } catch {
            progress("Своя подпись не создалась (\(error.localizedDescription)) — подпись будет временной.")
            return false
        }
        progress("Завёл свою подпись «\(localName)» в связке ключей — одна на этот Мак.")
        return true
    }

    // MARK: проба и выбор целиком

    /// Подписать копию `/usr/bin/true` личностью и запустить её: время подписи или nil — не вышло. Одного
    /// `--verify` мало: программа с этой подписью обязана запускаться.
    static func trial(_ sha1: String, run: Run) -> TimeInterval? {
        guard let folder = privateFolder() else { return nil }
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = folder.appendingPathComponent("pmp-sign-probe")
        guard (try? FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: copy)) != nil else {
            return nil
        }
        let start = Date()
        guard (try? run("/usr/bin/codesign", ["--force", "--sign", sha1, "--timestamp=none", copy.path],
                        signTimeout)) != nil else { return nil }
        let elapsed = Date().timeIntervalSince(start)
        guard (try? run(copy.path, [], 10)) != nil else { return nil }
        return elapsed
    }

    /// Две пробы: первая могла ждать окна связки ключей; вторая быстрая — «Всегда разрешать» нажали, и `--deep` по
    /// Claude окнами не посыплется. Обе долгие — в этот раз временная подпись.
    static func usable(_ sha1: String, trial: (String) -> TimeInterval?) -> Bool {
        guard let first = trial(sha1) else { return false }
        if first <= quickProbe { return true }
        guard let second = trial(sha1) else { return false }
        return second <= quickProbe
    }

    /// Личность для подписи Claude: список → выбор → при надобности своя (`create`) → проба. Годится — запоминается в
    /// `sign-identity.json`; nil — подпись будет временной (патч из-за подписи не ломается).
    public static func resolve(supportDirectory: URL, create: Bool, run: Run = shell,
                               progress: (String) -> Void = { _ in }) -> Choice? {
        let saved = load(from: supportDirectory)
        var choice = choose(listed(run), saved: saved)
        if choice == nil, create, createLocal(run: run, progress: progress) {
            choice = choose(listed(run), saved: saved)
        }
        guard let picked = choice else { return nil }
        if picked != saved { progress(passwordLine) }
        guard usable(picked.sha1, trial: { trial($0, run: run) }) else {
            progress("Постоянная подпись сейчас не выходит: macOS не дала ключ — ставлю временную.")
            return nil
        }
        if picked != saved { try? save(picked, to: supportDirectory) }
        return picked
    }

    static func listed(_ run: Run) -> [Candidate] {
        parse(findIdentity: (try? run("/usr/bin/security", ["find-identity", "-p", "codesigning"], 30)) ?? "")
    }

    // MARK: чем подписан Claude сейчас

    /// Подпись временная (ad-hoc)? nil — не подписан или не прочитать. Читает только подпись главного файла — дёшево.
    public static func isAdhoc(_ appURL: URL) -> Bool? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &code) == errSecSuccess, let code = code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        if let flags = dict[kSecCodeInfoFlags as String] as? NSNumber,
           flags.uint32Value & SecCodeSignatureFlags.adhoc.rawValue != 0 { return true }
        guard dict[kSecCodeInfoIdentifier as String] != nil else { return nil }
        let certificates = dict[kSecCodeInfoCertificates as String] as? [Any] ?? []
        return certificates.isEmpty
    }

    // MARK: служебное

    private static func privateFolder() -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pmp-sign-\(UUID().uuidString)",
                                                                                    isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            return folder
        } catch {
            return nil
        }
    }

    private static func randomHex() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
