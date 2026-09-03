import AppKit
import Foundation

// Порт claude-patch/patch-claude.mjs (команды patch / restore / status) на Swift.
// Отличия от mjs — по решениям критика плана WF4:
//   2 — Claude закрывается через NSRunningApplication.terminate/forceTerminate, не osascript;
//   3 — право на запись проверяется ДО закрытия Claude (промпт «Управление приложениями» всплывает первым);
//   4 — быстрый статус берётся из installed.json (версия + ElectronAsarIntegrity), без разбора asar;
//   6 — app.asar читается через Data(.mappedIfSafe);
//   8 — «Снять» = restore из бэкапа + переподпись ad-hoc.

public enum Patcher {
    public static let requiredLoaderVersion = Asar.loaderVersion
    public static let claudeBundleID = "com.anthropic.claudefordesktop"
    public static let supportDirName = "MyClaude" // лоадер v6 уже смотрит сюда — не переименовывать

    /// Значения по умолчанию для claude.json (настройки 👾 Элвиса из ElvisOS).
    public static let configDefaults: [String: Int] = ["minWindowWidth": 360, "sidePadding": 16]

    public static var defaultSupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(supportDirName, isDirectory: true)
    }

    /// Ресурсы внутри .app: entitlements.plist, inject.js, claude.css (кладёт tools/bundle.sh).
    public static var bundledResourcesDirectory: URL? {
        if let override = ProcessInfo.processInfo.environment["PIMPMYCLAUDE_RESOURCES"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return Bundle.main.resourceURL
    }

    /// Копии Claude.app, первой — та, которую macOS открывает по умолчанию.
    /// Launch Services помнит вообще всё, что когда-либо запускалось с этим bundle id: скрытые огрызки
    /// (`.Claude-before-….app`, `…app.failed`) и старые бэкапы. Из списка берём только настоящие
    /// установки в «Программах» — своих и системных, — иначе выбор превращается в список из тридцати папок.
    public static func locateClaude() -> [URL] {
        var found: [URL] = []
        var seen = Set<String>()
        func add(_ url: URL?) {
            guard let url = url, FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/Info.plist").path) else { return }
            let key = url.standardizedFileURL.resolvingSymlinksInPath().path
            if seen.insert(key).inserted { found.append(URL(fileURLWithPath: key, isDirectory: true)) }
        }
        let userApplications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        let folders = ["/Applications", userApplications.standardizedFileURL.path]

        add(NSWorkspace.shared.urlForApplication(withBundleIdentifier: claudeBundleID))
        for url in NSWorkspace.shared.urlsForApplications(withBundleIdentifier: claudeBundleID)
        where isRegularInstall(url, in: folders) { add(url) }
        add(URL(fileURLWithPath: "/Applications/Claude.app", isDirectory: true))
        add(userApplications.appendingPathComponent("Claude.app", isDirectory: true))
        return found
    }

    private static func isRegularInstall(_ url: URL, in folders: [String]) -> Bool {
        guard url.pathExtension == "app", !url.lastPathComponent.hasPrefix(".") else { return false }
        return folders.contains(url.deletingLastPathComponent().standardizedFileURL.path)
    }
}

// ------------------------------------------------------------------ ошибки

public enum PatchError: LocalizedError {
    case claudeNotFound
    case insideClaude
    case needsAppManagement(appPath: String, admin: Bool)
    case entitlementsMissing(String)
    case claudeWontQuit
    case noBackup(version: String, directory: String)
    case badInfoPlist(String)
    case tool(name: String, output: String)

    public var errorDescription: String? {
        switch self {
        case .claudeNotFound:
            return "Claude.app не найден. Скачай его с claude.ai/download и положи в «Программы»."
        case .insideClaude:
            return "Патч запущен изнутри Claude — он закроет сам себя. Закрой Claude Code в окне Claude и запусти PimpMyClaude из Finder."
        case .needsAppManagement(let appPath, let admin):
            let base = "macOS не пускает PimpMyClaude менять \(appPath).\n"
                + "Системные настройки → Конфиденциальность и безопасность → Управление приложениями → включи PimpMyClaude, потом нажми «Поставить» ещё раз."
            return admin ? base : base + "\n\nТы не администратор этого Мака: зайди под админом или переустанови Claude в свою папку ~/Applications."
        case .entitlementsMissing(let path):
            return "В сборке нет entitlements.plist (\(path)) — без него Claude после переподписи потеряет микрофон и экран."
        case .claudeWontQuit:
            return "Claude не закрывается — закрой все его окна вручную и нажми «Поставить» ещё раз."
        case .noBackup(let version, let directory):
            return "Бэкапа для Claude \(version) нет в \(directory). Настоящий откат — переустановить Claude с claude.ai/download."
        case .badInfoPlist(let path):
            return "Не читается \(path)"
        case .tool(let name, let output):
            return "\(name) не отработал: \(output)"
        }
    }
}

// ------------------------------------------------------------------ статус

/// Быстрый статус для меню-бара: версия Claude + ElectronAsarIntegrity против installed.json.
public enum ClaudeState: Equatable {
    case claudeNotFound
    case notInstalled(version: String)
    case lost(version: String, reason: String)
    case installed(version: String, loaderVersion: Int)

    public var menuTitle: String {
        switch self {
        case .claudeNotFound: return "Claude не найден"
        case .notInstalled(let version): return "Патч не стоит · Claude \(version)"
        case .lost(let version, let reason): return "Патч слетел (\(reason)) · Claude \(version)"
        case .installed(let version, let loader): return "Патч стоит · v\(loader) · Claude \(version)"
        }
    }

    public var isInstalled: Bool { if case .installed = self { return true }; return false }
}

/// Подробный статус (разбирает asar) — для окна «Статус…».
public struct ClaudeFullStatus {
    public let appPath: String
    public let version: String
    public let mainPath: String
    public let loaderVersion: Int
    public let headerSHA256: String
    public let infoPlistHash: String?
    public let signatureValid: Bool
    public let backupDirectory: String?
    public let configText: String?

    public var hashMatches: Bool { infoPlistHash == headerSHA256 }

    public var report: String {
        var lines = ["Claude \(version) — \(appPath)"]
        lines.append("Лоадер MyClaude: \(loaderVersion > 0 ? "v\(loaderVersion)" : "не стоит") (нужен v\(Patcher.requiredLoaderVersion))")
        lines.append("Главный сценарий: \(mainPath)")
        lines.append("Хэш asar в Info.plist \(hashMatches ? "совпадает" : "НЕ совпадает") с архивом")
        lines.append("Подпись Claude: \(signatureValid ? "валидна" : "НЕ валидна")")
        lines.append("Бэкап оригинала: \(backupDirectory ?? "нет")")
        lines.append("Настройки: \(configText ?? "файла нет, будут значения по умолчанию")")
        return lines.joined(separator: "\n")
    }
}

/// Чем кончилась установка.
public enum InstallOutcome {
    case alreadyInstalled(version: String)
    case repaired(version: String)
    case installed(version: String)
}

// ------------------------------------------------------------------ патчер

public struct ClaudePatcher {
    public var appURL: URL
    public var supportDirectory: URL
    /// Где лежат entitlements.plist, inject.js, claude.css. nil — живые файлы не обновляем.
    public var resourcesDirectory: URL?
    /// Тест патчит копию: подписывать нечего и Claude трогать нельзя.
    public var signsApp = true
    public var managesClaudeProcess = true

    public init(appURL: URL,
                supportDirectory: URL = Patcher.defaultSupportDirectory,
                resourcesDirectory: URL? = Patcher.bundledResourcesDirectory) {
        self.appURL = appURL
        self.supportDirectory = supportDirectory
        self.resourcesDirectory = resourcesDirectory
    }

    var asarURL: URL { appURL.appendingPathComponent("Contents/Resources/app.asar") }
    var infoPlistURL: URL { appURL.appendingPathComponent("Contents/Info.plist") }
    var configURL: URL { supportDirectory.appendingPathComponent("claude.json") }
    var installedURL: URL { supportDirectory.appendingPathComponent("installed.json") }
    func backupDirectory(_ version: String) -> URL {
        supportDirectory.appendingPathComponent("backups", isDirectory: true).appendingPathComponent(version, isDirectory: true)
    }

    // -------------------------------------------------------------- Поставить

    /// Порядок по решению 3: найти → проверить запись (промпт App Management ДО закрытия Claude)
    /// → закрыть → бэкап → патч → хэш → ad-hoc подпись → открыть Claude.
    @discardableResult
    public func install(progress: (String) -> Void = { _ in }) throws -> InstallOutcome {
        try refuseIfInsideClaude()
        let version = try appVersion()
        let entitlements = try entitlementsURL()
        try ensureConfig()

        let before = try Asar.status(of: asarURL)
        progress("Claude \(version), главный сценарий \(before.mainPath), лоадер сейчас: \(before.loaderVersion > 0 ? "v\(before.loaderVersion)" : "нет")")
        progress("Настройки \(configURL.path)")

        if before.loaderVersion == Patcher.requiredLoaderVersion {
            // Лоадер есть, но прошлый прогон мог упасть между записью архива и подписью:
            // тогда хэш в Info.plist или подпись протухли, и Claude не запустится.
            if infoPlistHash() == before.headerSHA256 && (!signsApp || signatureValid()) {
                progress("Патч уже стоит. Обновляю только живые файлы в Application Support.")
                try installLiveFiles(progress: progress)
                try writeInstalled(version: version, headerSHA256: before.headerSHA256, mainPath: before.mainPath)
                return .alreadyInstalled(version: version)
            }
            progress("Лоадер стоит, но хэш или подпись не сходятся — дочиню.")
            try waitForWritable(progress: progress)
            try quitClaude(progress: progress)
            try setInfoPlistHash(before.headerSHA256)
            try signAndVerify(entitlements: entitlements, progress: progress)
            try installLiveFiles(progress: progress)
            try writeInstalled(version: version, headerSHA256: before.headerSHA256, mainPath: before.mainPath)
            relaunchClaude()
            return .repaired(version: version)
        }

        try waitForWritable(progress: progress)
        try quitClaude(progress: progress)
        try makeBackup(version: version, progress: progress)
        progress("Ставлю лоадер в app.asar…")
        let result = try Asar.patch(asarURL)
        try setInfoPlistHash(result.headerSHA256)
        try signAndVerify(entitlements: entitlements, progress: progress)
        try installLiveFiles(progress: progress)
        try writeInstalled(version: version, headerSHA256: result.headerSHA256, mainPath: result.mainPath)
        progress("Готово. Открываю Claude…")
        relaunchClaude()
        progress("Если macOS заново спросит разрешения (микрофон, экран) — это из-за новой подписи, один раз.")
        return .installed(version: version)
    }

    // -------------------------------------------------------------- Снять

    /// Решение 8: возврат оригинальных файлов из бэкапа + переподпись ad-hoc.
    /// Подпись Apple при этом не возвращается — честный откат только переустановкой Claude.
    public func restore(progress: (String) -> Void = { _ in }) throws {
        try refuseIfInsideClaude()
        let version = try appVersion()
        let directory = backupDirectory(version)
        let backupAsar = directory.appendingPathComponent("app.asar")
        let backupInfo = directory.appendingPathComponent("Info.plist")
        guard FileManager.default.fileExists(atPath: backupAsar.path) else {
            throw PatchError.noBackup(version: version, directory: directory.path)
        }
        let entitlements = try entitlementsURL()
        try waitForWritable(progress: progress)
        try quitClaude(progress: progress)
        progress("Возвращаю оригинальные app.asar и Info.plist \(version)…")
        try Data(contentsOf: backupAsar, options: .mappedIfSafe).write(to: asarURL, options: .atomic)
        if FileManager.default.fileExists(atPath: backupInfo.path) {
            try Data(contentsOf: backupInfo).write(to: infoPlistURL, options: .atomic)
        }
        try signAndVerify(entitlements: entitlements, progress: progress)
        try? FileManager.default.removeItem(at: installedURL)
        progress("Готово. Подпись осталась локальной — подпись Apple вернёт только переустановка Claude. Открываю Claude…")
        relaunchClaude()
    }

    // -------------------------------------------------------------- Статус

    /// Быстрый статус (решение 4): версия + ElectronAsarIntegrity против installed.json.
    /// Если installed.json нет или не сходится — один разбор asar, чтобы не соврать про чужую
    /// установку (патч мог поставить старый patch-claude.mjs); удачную находку записываем.
    public func state() -> ClaudeState {
        guard let version = try? appVersion() else { return .claudeNotFound }
        let recorded = installedRecord()
        let currentHash = infoPlistHash()
        if let recorded = recorded, recorded.version == version, recorded.headerSHA256 == currentHash, currentHash != nil {
            return .installed(version: version, loaderVersion: recorded.loaderVersion)
        }
        guard let asar = try? Asar.status(of: asarURL) else {
            return recorded == nil ? .notInstalled(version: version) : .lost(version: version, reason: "app.asar не читается")
        }
        if asar.loaderVersion == Patcher.requiredLoaderVersion && currentHash == asar.headerSHA256 {
            try? writeInstalled(version: version, headerSHA256: asar.headerSHA256, mainPath: asar.mainPath)
            return .installed(version: version, loaderVersion: asar.loaderVersion)
        }
        let reason: String
        if asar.loaderVersion == 0 { reason = "Claude обновился" }
        else if asar.loaderVersion != Patcher.requiredLoaderVersion { reason = "старый лоадер v\(asar.loaderVersion)" }
        else { reason = "хэш в Info.plist не сходится" }
        return recorded == nil ? .notInstalled(version: version) : .lost(version: version, reason: reason)
    }

    /// Подробный статус — как `patch-claude.mjs status`.
    public func fullStatus() throws -> ClaudeFullStatus {
        let version = try appVersion()
        let asar = try Asar.status(of: asarURL)
        let backup = backupDirectory(version)
        let hasBackup = FileManager.default.fileExists(atPath: backup.appendingPathComponent("app.asar").path)
        let config = try? String(contentsOf: configURL, encoding: .utf8)
        return ClaudeFullStatus(appPath: appURL.path,
                                version: version,
                                mainPath: asar.mainPath,
                                loaderVersion: asar.loaderVersion,
                                headerSHA256: asar.headerSHA256,
                                infoPlistHash: infoPlistHash(),
                                signatureValid: signatureValid(),
                                backupDirectory: hasBackup ? backup.path : nil,
                                configText: config?.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces))
    }

    // -------------------------------------------------------------- Info.plist

    public func appVersion() throws -> String {
        guard let data = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let version = plist["CFBundleShortVersionString"] as? String else {
            throw PatchError.badInfoPlist(infoPlistURL.path)
        }
        return version
    }

    func infoPlistHash() -> String? {
        guard let data = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let integrity = plist["ElectronAsarIntegrity"] as? [String: Any],
              let entry = integrity["Resources/app.asar"] as? [String: Any] else { return nil }
        return entry["hash"] as? String
    }

    /// PlistBuddy правит один ключ и не переписывает файл — как в mjs.
    /// Не вышло (нет PlistBuddy, битый plist) — пишем целиком через PropertyListSerialization.
    func setInfoPlistHash(_ hash: String) throws {
        let buddy = "/usr/libexec/PlistBuddy"
        if FileManager.default.isExecutableFile(atPath: buddy),
           (try? Shell.run(buddy, ["-c", "Set :ElectronAsarIntegrity:Resources/app.asar:hash \(hash)", infoPlistURL.path])) != nil,
           infoPlistHash() == hash {
            return
        }
        guard let data = try? Data(contentsOf: infoPlistURL),
              var plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw PatchError.badInfoPlist(infoPlistURL.path)
        }
        var integrity = plist["ElectronAsarIntegrity"] as? [String: Any] ?? [:]
        var entry = integrity["Resources/app.asar"] as? [String: Any] ?? ["algorithm": "SHA256"]
        entry["hash"] = hash
        integrity["Resources/app.asar"] = entry
        plist["ElectronAsarIntegrity"] = integrity
        let out = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try out.write(to: infoPlistURL, options: .atomic)
    }

    // -------------------------------------------------------------- подпись

    func entitlementsURL() throws -> URL? {
        guard signsApp else { return nil }
        guard let directory = resourcesDirectory else { throw PatchError.entitlementsMissing("ресурсы приложения не найдены") }
        let url = directory.appendingPathComponent("entitlements.plist")
        guard FileManager.default.fileExists(atPath: url.path) else { throw PatchError.entitlementsMissing(url.path) }
        return url
    }

    func signAndVerify(entitlements: URL?, progress: (String) -> Void) throws {
        guard signsApp, let entitlements = entitlements else { return }
        progress("Переподписываю Claude локальной подписью…")
        try Shell.run("/usr/bin/xattr", ["-cr", appURL.path])
        try Shell.run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", "--timestamp=none", appURL.path])
        try Shell.run("/usr/bin/codesign", ["--force", "--sign", "-", "--timestamp=none", "--entitlements", entitlements.path, appURL.path])
        try Shell.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=2", appURL.path])
    }

    func signatureValid() -> Bool {
        (try? Shell.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", appURL.path])) != nil
    }

    // -------------------------------------------------------------- права на запись

    /// Решение 3: пробная запись в Contents/Resources. Первая неудача поднимает системный промпт
    /// «Управление приложениями»; после «Разрешить» следующая проба проходит и установка едет дальше.
    func waitForWritable(timeout: TimeInterval = 60, progress: (String) -> Void) throws {
        let probe = appURL.appendingPathComponent("Contents/Resources/.pimpmyclaude-write-test")
        var announced = false
        let started = Date()
        let deadline = started.addingTimeInterval(timeout)
        while true {
            let errno = writeProbe(probe)
            if errno == 0 { return }
            // EACCES обычно означает чужого владельца (промпта не будет), но на новых macOS отказ
            // «Управления приложениями» тоже может прийти как EACCES — даём промпту 10 с, потом сдаёмся.
            if errno == EACCES, Date().timeIntervalSince(started) > 10 {
                throw PatchError.needsAppManagement(appPath: appURL.path, admin: currentUserIsAdmin())
            }
            if !announced {
                announced = true
                progress("macOS спрашивает разрешение «Управление приложениями» — нажми «Разрешить», дальше сам.")
            }
            if Date() >= deadline {
                throw PatchError.needsAppManagement(appPath: appURL.path, admin: currentUserIsAdmin())
            }
            Thread.sleep(forTimeInterval: 0.75)
        }
    }

    /// 0 — записалось; иначе errno (EPERM — App Management, EACCES — чужой владелец).
    private func writeProbe(_ probe: URL) -> Int32 {
        let fd = open(probe.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        if fd < 0 { return errno }
        close(fd)
        unlink(probe.path)
        return 0
    }

    private func currentUserIsAdmin() -> Bool {
        guard let group = getgrnam("admin") else { return false }
        let admin = group.pointee.gr_gid
        var list = [gid_t](repeating: 0, count: 128)
        let count = getgroups(Int32(list.count), &list)
        guard count > 0 else { return false }
        return list.prefix(Int(count)).contains(admin)
    }

    // -------------------------------------------------------------- процессы Claude

    /// Решение 2: свои процессы ищем по bundleURL, закрываем terminate → forceTerminate.
    func runningClaude() -> [NSRunningApplication] {
        let base = appURL.standardizedFileURL.resolvingSymlinksInPath().path
        return NSWorkspace.shared.runningApplications.filter { app in
            guard let bundle = app.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path else { return false }
            return bundle == base || bundle.hasPrefix(base + "/")
        }
    }

    func quitClaude(progress: (String) -> Void) throws {
        guard managesClaudeProcess else { return }
        let running = runningClaude()
        guard !running.isEmpty else { return }
        progress("Закрываю Claude…")
        running.forEach { $0.terminate() }
        if waitUntilClosed(seconds: 20) { return }
        runningClaude().forEach { $0.forceTerminate() }
        if waitUntilClosed(seconds: 10) { return }
        throw PatchError.claudeWontQuit
    }

    private func waitUntilClosed(seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if runningClaude().isEmpty { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return runningClaude().isEmpty
    }

    func relaunchClaude() {
        guard managesClaudeProcess else { return }
        _ = try? Shell.run("/usr/bin/open", ["-a", appURL.path])
    }

    /// Патч нельзя запускать изнутри самого Claude (Claude Code в его окне): закрытие Claude убило бы
    /// и запустившего. Смотрим цепочку родителей — как refuseIfInsideClaude в mjs.
    func refuseIfInsideClaude() throws {
        guard managesClaudeProcess else { return }
        let inside = appURL.standardizedFileURL.resolvingSymlinksInPath().path + "/Contents/"
        var pid = getpid()
        for _ in 0..<30 where pid > 1 {
            if let path = Processes.executablePath(of: pid), path.hasPrefix(inside) { throw PatchError.insideClaude }
            guard let parent = Processes.parentPID(of: pid), parent != pid else { return }
            pid = parent
        }
    }

    // -------------------------------------------------------------- бэкап и живые файлы

    func makeBackup(version: String, progress: (String) -> Void) throws {
        let directory = backupDirectory(version)
        let asar = directory.appendingPathComponent("app.asar")
        let info = directory.appendingPathComponent("Info.plist")
        if FileManager.default.fileExists(atPath: asar.path) && FileManager.default.fileExists(atPath: info.path) { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        progress("Сохраняю оригинал Claude \(version) в \(directory.path)…")
        try Data(contentsOf: asarURL, options: .mappedIfSafe).write(to: asar, options: .atomic)
        try Data(contentsOf: infoPlistURL).write(to: info, options: .atomic)
    }

    /// claude.json создаётся значениями по умолчанию и НИКОГДА не перезаписывается.
    func ensureConfig() throws {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: configURL.path) else { return }
        let data = try JSONSerialization.data(withJSONObject: Patcher.configDefaults, options: [.prettyPrinted, .sortedKeys])
        try (data + Data("\n".utf8)).write(to: configURL, options: .atomic)
    }

    /// inject.js и claude.css — живые файлы лоадера v6; при установке обновляем на версию из сборки.
    func installLiveFiles(progress: (String) -> Void) throws {
        try ensureConfig()
        guard let directory = resourcesDirectory else { return }
        for name in ["inject.js", "claude.css"] {
            let source = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            try Data(contentsOf: source).write(to: supportDirectory.appendingPathComponent(name), options: .atomic)
        }
        progress("Живые файлы в \(supportDirectory.path) обновлены.")
    }

    // -------------------------------------------------------------- installed.json

    struct InstalledRecord {
        let version: String
        let headerSHA256: String
        let loaderVersion: Int
    }

    func installedRecord() -> InstalledRecord? {
        guard let data = try? Data(contentsOf: installedURL),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let version = json["version"] as? String,
              let hash = json["headerSHA256"] as? String else { return nil }
        return InstalledRecord(version: version, headerSHA256: hash, loaderVersion: json["loaderVersion"] as? Int ?? Patcher.requiredLoaderVersion)
    }

    func writeInstalled(version: String, headerSHA256: String, mainPath: String) throws {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let record: [String: Any] = [
            "appPath": appURL.path,
            "version": version,
            "headerSHA256": headerSHA256,
            "loaderVersion": Patcher.requiredLoaderVersion,
            "mainPath": mainPath,
            "at": ISO8601DateFormatter().string(from: Date()),
        ]
        let data = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: installedURL, options: .atomic)
    }
}

// ------------------------------------------------------------------ подпроцессы и процессы

enum Shell {
    /// stdout и stderr в одну трубу: одно чтение до конца, дедлока на переполнении буфера нет.
    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch {
            throw PatchError.tool(name: (launchPath as NSString).lastPathComponent, output: error.localizedDescription)
        }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw PatchError.tool(name: (launchPath as NSString).lastPathComponent, output: text.isEmpty ? "код \(process.terminationStatus)" : text)
        }
        return text
    }
}

enum Processes {
    static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }
}
