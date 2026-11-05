import Foundation
import Security
import SQLite3

/// Доступы Claude в macOS (#10252; Элвис 19.10: «А может Пимп в значке, если доступа у Клауда нету, прямо помечать,
/// чтобы не забывать каждый раз после обновления все доступы давать»).
///
/// Почему слетают: патч переподписывает Claude ad-hoc, у каждой сборки свой cdhash, а macOS хранит доступ вместе с
/// требованием к подписи (`csreq`). Новая подпись требованию не отвечает — в Настройках выключатель стоит, а доступа
/// нет (замер 19.10: «Полный доступ к диску» записан под cdhash сборки, «Универсальный доступ» — под подписью
/// Anthropic, то есть не работает с первого патча).
///
/// Читаем системную базу TCC — её читает только программа с «Полным доступом к диску»; у Пимпа его нет — `.unknown`.
public enum ClaudeAccess {
    public enum Service: String, CaseIterable {
        case fullDisk = "kTCCServiceSystemPolicyAllFiles"
        case accessibility = "kTCCServiceAccessibility"
        case screen = "kTCCServiceScreenCapture"

        public var title: String {
            switch self {
            case .fullDisk: return "Полный доступ к диску"
            case .accessibility: return "Универсальный доступ"
            case .screen: return "Запись экрана"
            }
        }

        /// Лист Системных настроек с этим доступом.
        public var settingsURL: URL {
            let anchor: String
            switch self {
            case .fullDisk: anchor = "Privacy_AllFiles"
            case .accessibility: anchor = "Privacy_Accessibility"
            case .screen: anchor = "Privacy_ScreenCapture"
            }
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
        }

        /// Имя доступа для `tccutil reset` (#10310).
        public var tccName: String { String(rawValue.dropFirst("kTCCService".count)) }
    }

    /// Что с одним доступом Claude (#10310): дан и действует; дан под этой подписью, но выключен; записан под
    /// старой подписью (выключатель горит, а macOS нового Claude не признаёт — снять запись и выдать заново);
    /// записи нет — ни разу не давали или сняли.
    public enum Grant: Equatable { case granted, off, stale, absent }

    public enum State: Equatable {
        /// Базу не прочитать: у Пимпа нет «Полного доступа к диску».
        case unknown
        case ok
        case missing([Service])
    }

    /// Строка базы: доступ, ответ человека (2 — разрешено) и требование к подписи.
    public struct Record: Equatable {
        public let service: Service
        public let allowed: Bool
        public let csreq: Data?
        public init(service: Service, allowed: Bool, csreq: Data?) {
            self.service = service
            self.allowed = allowed
            self.csreq = csreq
        }
    }

    /// Чего не хватает: доступ когда-то давали (строка есть), а теперь он выключен или подпись Claude требованию не
    /// отвечает. Ни разу не дававшееся не просим — у команды Claude может жить и без этих доступов.
    public static func evaluate(_ records: [Record], matches: (Data) -> Bool) -> State {
        state(of: grants(records, matches: matches))
    }

    /// Каждый доступ по строке базы: требование к подписи не подходит — `stale` (выключатель тут не поможет), иначе
    /// выключен — `off`; нет строки — `absent`.
    public static func grants(_ records: [Record], matches: (Data) -> Bool) -> [Service: Grant] {
        var out: [Service: Grant] = [:]
        for service in Service.allCases {
            guard let record = records.first(where: { $0.service == service }) else {
                out[service] = .absent
                continue
            }
            if !(record.csreq.map(matches) ?? true) { out[service] = .stale } else { out[service] = record.allowed ? .granted : .off }
        }
        return out
    }

    /// Состояние по доступам: слетевшие — выключенные и записанные под старой подписью.
    public static func state(of grants: [Service: Grant]) -> State {
        let missing = Service.allCases.filter { grants[$0] == .off || grants[$0] == .stale }
        return missing.isEmpty ? .ok : .missing(missing)
    }

    static let systemDB = "/Library/Application Support/com.apple.TCC/TCC.db"

    /// Проверка на диске: база TCC и подпись Claude по `appURL`. Не на главной нитке.
    public static func check(appURL: URL, bundleID: String) -> State {
        grants(appURL: appURL, bundleID: bundleID).map(state(of:)) ?? .unknown
    }

    /// Доступы Claude по базе TCC и его подписи; nil — базу не прочитать (`.unknown`). Не на главной нитке.
    public static func grants(appURL: URL, bundleID: String) -> [Service: Grant]? {
        guard let records = read(bundleID: bundleID) else { return nil }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &code) == errSecSuccess, let code = code else { return nil }
        return grants(records) { csreq in
            var requirement: SecRequirement?
            guard SecRequirementCreateWithData(csreq as CFData, [], &requirement) == errSecSuccess,
                  let requirement = requirement else { return false }
            // Только требование к подписи: хэши всех файлов огромного Claude раз в минуту не пересчитываем.
            let flags = SecCSFlags(rawValue: kSecCSDoNotValidateResources | kSecCSDoNotValidateExecutable)
            return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
        }
    }

    /// Снять запись доступа (#10310): «удалить и перенести заново» без кнопки «−». Удалось ли — смотри по базе
    /// (`grants`): код возврата `tccutil` этого не доказывает. Не на главной нитке.
    @discardableResult
    public static func reset(_ service: Service, bundleID: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service.tccName, bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        let deadline = Date().addingTimeInterval(10)
        while process.isRunning, Date() < deadline { usleep(50_000) }
        guard !process.isRunning else {
            process.terminate()
            return false
        }
        return process.terminationStatus == 0
    }

    static func read(bundleID: String, path: String = systemDB) -> [Record]? {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "SELECT service, auth_value, csreq FROM access WHERE client = ?1 AND client_type = 0"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, bundleID, -1, transient)
        var out: [Record] = []
        while true {
            let step = sqlite3_step(statement)
            guard step == SQLITE_ROW else { return step == SQLITE_DONE ? out : nil }
            guard let raw = sqlite3_column_text(statement, 0),
                  let service = Service(rawValue: String(cString: raw)) else { continue }
            var csreq: Data?
            if let blob = sqlite3_column_blob(statement, 2) {
                csreq = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 2)))
            }
            out.append(Record(service: service, allowed: sqlite3_column_int(statement, 1) == 2, csreq: csreq))
        }
    }
}
