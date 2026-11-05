import AppKit
import Foundation

// Порт claude-patch/patch-claude.mjs (команды patch / restore / status) на Swift.
// Отличия от mjs — по решениям критика плана WF4:
//   2 — Claude закрывается через NSRunningApplication.terminate/forceTerminate, не osascript;
//   3 — право на запись проверяется ДО закрытия Claude (ждём «Управление приложениями», Claude ещё открыт);
//   4 — быстрый статус берётся из installed.json (версия + ElectronAsarIntegrity), без разбора asar;
//   6 — app.asar читается через Data(.mappedIfSafe);
//   8 — «Снять патч…» = restore из бэкапа + переподпись (с #10310 — постоянной, `SignIdentity`; не вышла — ad-hoc).

public enum Patcher {
    public static let requiredLoaderVersion = Asar.loaderVersion
    public static let claudeBundleID = "com.anthropic.claudefordesktop"
    public static let supportDirName = "MyClaude" // лоадер смотрит сюда (Loader.swift) — не переименовывать
    /// Комплект воркфлоу: `resources/workflow-kit` в бандле → `MyClaude/workflow` рядом с
    /// command.json (решение 3 плана WF9). Имя папки в Application Support знает текст KICKOFF.md.
    public static let workflowKitDirName = "workflow-kit"
    public static let workflowDirName = "workflow"

    /// Значения по умолчанию для claude.json (настройки 👾 Элвиса из ElvisOS).
    /// `sidePadding: 24` — слово Элвиса 08.10.2026 (WF128; было 5 с 04.09). Отсюда же его берёт
    /// `LiveStyle.defaultSidePadding`; та же цифра — в `claude-patch/claude.json` и `DEFAULTS` в `patch-claude.mjs`.
    /// На существующих установках это ничего не меняет:
    /// `ensureConfig` готовый файл не перезаписывает.
    /// `minWindowWidth: 280` (WF45, задача #5751) — у Элвиса в живом файле стоит 280, у команды
    /// приезжало 360, и из-за этого две плитки раскладок из четырёх были серыми (ячейка уже
    /// минимальной ширины окна). Та же цифра — в `claude-patch/claude.json`.
    /// `windowGap: 5` (WF77, задача #6734) — зазор между окнами при расстановке, столько же
    /// у Элвиса стоит живьём. Пункта меню у ключа нет, правится руками; ключа нет вовсе —
    /// `ClaudeActions.windowGap()` подставит отсюда же те же 5, так что у команды ничего не поедет.
    public static let configDefaults: [String: Int] = [
        "minWindowWidth": 280, "sidePadding": 24, "windowGap": 5,
    ]

    /// Сколько шаг записи ждёт, что человек включит «Управление приложениями» (#9842): с запасом на пароль Мака.
    public static let permissionWaitSeconds: TimeInterval = 600
    /// Строка журнала: запись в Claude.app не пускает «Управление приложениями». По ней приложение открывает
    /// Системные настройки и ставит подсказку (`PimpPanelText.patchStep` и `installStep` её узнают).
    public static let appManagementWaitLine = "Нужно право «Управление приложениями»: включи PimpMyClaude в Системных настройках — дальше сам."
    /// Строка журнала: Claude не закрылся и после принудительного выхода — ждём, что закроет человек.
    public static let claudeQuitWaitLine = "Claude не закрывается — закрой его сам (меню Claude → Завершить), дальше сам."
    /// Строка журнала: Claude.app чужой — сейчас macOS спросит пароль, чтобы сделать его своим.
    public static func ownershipLine(_ owner: String) -> String {
        PatchLog.ownership + " пользователю «\(owner)» — macOS спросит пароль Мака, чтобы сделать его твоим…"
    }
    /// Сколько `quitClaude` ждёт человека после принудительного выхода.
    public static let claudeQuitUserSeconds: TimeInterval = 120

    /// Отмена ожидания права — кнопкой подсказки; шаг записи бросит `PatchError.cancelled`.
    public static func cancelPermissionWait() { permissionWait.cancel() }
    static let permissionWait = CancelFlag()

    /// Можно ли создать файл в папке с такими правами по одним POSIX-битам (запись и вход).
    public static func posixWritable(mode: mode_t, owner: uid_t, group: gid_t, uid: uid_t, groups: [gid_t]) -> Bool {
        if uid == 0 { return true }
        let need: mode_t
        if owner == uid { need = S_IWUSR | S_IXUSR } else if groups.contains(group) { need = S_IWGRP | S_IXGRP } else { need = S_IWOTH | S_IXOTH }
        return mode & need == need
    }

    public static let cssFileName = SupportFiles.cssFileName
    /// Маркеры авто-блока живого claude.css; ими же пишет блок полей `LiveStyle` (ClaudeAX видит Patcher с WF247).
    public static let cssMarkerStart = "/* PimpMyClaude:auto */"
    public static let cssMarkerEnd = "/* /PimpMyClaude:auto */"

    /// Слияние claude.css при установке (WF45, задача #5723). Приложение владеет РОВНО одним
    /// блоком между маркерами; всё, что человек дописал вне блока, остаётся дословно — это
    /// обещает `docs/TEAM.md`. Живого файла нет — кладём файл из бандла целиком; в бандле блока нет — живой не трогаем.
    public static func mergeCSS(bundled: String, live: String?) -> String {
        guard let live = live else { return bundled }
        guard let block = cssBlock(of: bundled) else { return live }
        return applyingCSSBlock(block, to: live)
    }

    /// Блок в текст claude.css (им же пишет ползунок полей, `LiveStyle.writeBlock`): оба маркера по разу — замена
    /// между ними на месте; маркеров нет — блок в КОНЕЦ (последний выигрывает по каскаду); маркеры битые или блок
    /// задвоился — мусор от первого маркера до последнего вырезается, блок в конец. Чужие строки — дословно.
    public static func applyingCSSBlock(_ block: [String], to live: String) -> String {
        var lines = live.components(separatedBy: "\n")
        // Хвост после последнего перевода строки — не строка файла; финальный \n добавим сами.
        if lines.last?.isEmpty == true { lines.removeLast() }
        let starts = lines.indices.filter { isCSSMarker(lines[$0], cssMarkerStart) }
        let ends = lines.indices.filter { isCSSMarker(lines[$0], cssMarkerEnd) }
        if starts.count == 1, ends.count == 1, starts[0] < ends[0] {
            lines.replaceSubrange(starts[0]...ends[0], with: block)
        } else {
            // Маркеров нет, они битые или блок задвоился: старый мусор вырезаем от первого
            // маркера до последнего и дописываем блок в конец (последний выигрывает по каскаду).
            if let first = (starts + ends).min(), let last = (starts + ends).max() {
                lines.removeSubrange(first...last)
            }
            while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
            lines += block
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Строки авто-блока файла из бандла (от маркера до маркера включительно); блока нет — nil.
    private static func cssBlock(of text: String) -> [String]? {
        let lines = text.components(separatedBy: "\n")
        guard let start = lines.indices.first(where: { isCSSMarker(lines[$0], cssMarkerStart) }),
              let end = lines.indices.last(where: { isCSSMarker(lines[$0], cssMarkerEnd) }),
              start < end else { return nil }
        return Array(lines[start...end])
    }

    private static func isCSSMarker(_ line: String, _ marker: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == marker
    }

    /// Редакция страницы из её же текста: строка `const VERSION = "wf79-a-1";` → (79, "a", 1).
    /// Метки нет или она незнакомого вида — nil.
    public static func injectVersion(of text: String) -> (Int, String, Int)? {
        guard let head = text.range(of: "const VERSION = \"") else { return nil }
        let rest = text[head.upperBound...]
        guard let tail = rest.firstIndex(of: "\"") else { return nil }
        let parts = rest[rest.startIndex..<tail].components(separatedBy: "-")
        guard parts.count == 3, parts[0].hasPrefix("wf"), !parts[1].isEmpty,
              let wave = Int(parts[0].dropFirst(2)), let step = Int(parts[2]) else { return nil }
        return (wave, parts[1], step)
    }

    /// Установка не отнимает фичи (задача #7035, случай 22.09.2026): приложение несёт копию
    /// `inject.js` с той минуты, когда его собрали, а живую страницу с тех пор могли поправить
    /// не одну волну. Живая редакция СТАРШЕ той, что в сборке, — живую оставляем: «Пропатчить
    /// Claude» после обновления Claude чинит патч, а не откатывает страницу на две волны назад.
    /// Редакция не читается хоть у одного из двоих — кладём файл из сборки, как было до WF79.
    public static func injectKeepsLive(bundled: String, live: String?) -> Bool {
        guard let live = live,
              let liveVersion = injectVersion(of: live),
              let bundledVersion = injectVersion(of: bundled) else { return false }
        if liveVersion.0 != bundledVersion.0 { return liveVersion.0 > bundledVersion.0 }
        if liveVersion.1 != bundledVersion.1 { return liveVersion.1 > bundledVersion.1 }
        return liveVersion.2 > bundledVersion.2
    }

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
            // Предпочтительная копия Launch Services тоже бывает огрызком: 23.09 ею оказалась
            // скрытая `.Claude-before-Matrix-1.20186.1.app` — «Пропатчить Claude» её пропатчил и запустил
            // вторым Claude рядом с настоящим (#7096).
            guard isVisibleInstall(URL(fileURLWithPath: key, isDirectory: true)) else { return }
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

    /// Копия, которую можно показывать и патчить (#7096): `.app`, и ни имя, ни одна папка пути
    /// не скрытые — мимо идут `.Claude-before-….app`, `….app.failed` и корзина. Где лежит копия,
    /// не проверяем: у команды Claude бывает не только в «Программах». Чистая — под тестом.
    public static func isVisibleInstall(_ url: URL) -> Bool {
        let url = url.standardizedFileURL
        guard url.pathExtension == "app" else { return false }
        return !url.pathComponents.contains { $0.hasPrefix(".") }
    }

    /// Сохранённый выбор копии Claude (`claudeAppPath`, #7096): годится, только если это видимая
    /// копия из нынешнего списка. `forget` — путь не проходит `isVisibleInstall`, его пора стереть:
    /// иначе выбор так и держался бы за скрытую копию. Чистая — под тестом.
    public static func savedClaude(_ saved: String?, among copies: [URL]) -> (url: URL?, forget: Bool) {
        guard let saved = saved else { return (nil, false) }
        guard isVisibleInstall(URL(fileURLWithPath: saved, isDirectory: true)) else { return (nil, true) }
        return (copies.first { $0.path == saved }, false)
    }
}

// ------------------------------------------------------------------ ошибки

public enum PatchError: LocalizedError {
    case claudeNotFound
    case insideClaude
    case needsAppManagement(appPath: String, admin: Bool)
    /// POSIX не пускает: Claude.app чужой (#9842), и сделать его своим под паролем Мака не вышло.
    case ownershipFailed(owner: String, why: String)
    /// Человек отменил ожидание права.
    case cancelled
    /// Право дали, но этот процесс macOS не пускает до перезапуска — приложение перезапускается и доделывает.
    case needsRelaunch
    case entitlementsMissing(String)
    case claudeWontQuit
    case noBackup(version: String, directory: String)
    case badInfoPlist(String)
    case installBroke(why: String, restored: Bool)
    case tool(name: String, output: String)
    /// Второй замок Electron 41+ включён (A2): патч не ставим, Claude не закрываем.
    case integrityDigestOn(version: String, why: String)

    public var errorDescription: String? {
        switch self {
        case .claudeNotFound:
            return "Claude.app не найден. Скачай его с claude.ai/download и положи в «Программы»."
        case .insideClaude:
            return "Патч запущен изнутри Claude — он закроет сам себя. Закрой Claude Code в окне Claude и запусти PimpMyClaude из Finder."
        case .needsAppManagement(let appPath, let admin):
            let base = "macOS не пускает PimpMyClaude менять \(appPath).\n"
                + "Нажми «Открыть настройки» и включи PimpMyClaude в «Управление приложениями» (нет в списке — «+» и выбери его в «Программах»), потом «Ещё раз»."
            return admin ? base : base + "\n\nТы не администратор этого Мака: macOS спросит имя и пароль администратора — попроси его."
        case .ownershipFailed(let owner, let why):
            return "Claude.app принадлежит пользователю «\(owner)», не тебе, а сделать его твоим не вышло: \(why).\n"
                + "Нажми «Ещё раз» и введи пароль Мака (не администратор — имя и пароль администратора)."
        case .cancelled:
            return "Отменено — Claude не тронут."
        case .needsRelaunch:
            return "Право дали — перезапускаю PimpMyClaude, патч продолжится сам."
        case .entitlementsMissing(let path):
            return "В сборке нет entitlements.plist (\(path)) — без него Claude после переподписи потеряет микрофон и экран."
        case .claudeWontQuit:
            return "Claude не закрылся. Закрой его сам (меню Claude → Завершить или «Завершить принудительно» в Мониторинге системы) и нажми «Ещё раз»."
        case .noBackup(let version, let directory):
            return "Бэкапа для Claude \(version) нет в \(directory). Настоящий откат — переустановить Claude с claude.ai/download."
        case .badInfoPlist(let path):
            return "Не читается \(path)"
        case .installBroke(let why, let restored):
            let base = "Патч не встал: \(why)\n\n"
            return restored
                ? base + "Оригинальный Claude вернулся из бэкапа — он запускается. Нажми «Пропатчить Claude» ещё раз."
                : base + "Claude сейчас может не запуститься. Нажми «Пропатчить Claude» ещё раз — приложение дочинит хэш и подпись; "
                    + "не помогло — «Снять патч…» (панель у часов › Настройки › Обновления) или переустанови Claude с claude.ai/download."
        case .tool(let name, let output):
            return "\(name) не отработал: \(output)"
        case .integrityDigestOn(let version, let why):
            return "Claude \(version) PMP пока не патчит: \(why). Claude не тронут — он запускается как был."
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
    /// Все копии Claude на Маке — их бэкапы уборка не трогает (G3 WF101). Тест подменяет.
    public var claudeCopies: () -> [URL] = { Patcher.locateClaude() }

    public init(appURL: URL,
                supportDirectory: URL = Patcher.defaultSupportDirectory,
                resourcesDirectory: URL? = Patcher.bundledResourcesDirectory) {
        self.appURL = appURL
        self.supportDirectory = supportDirectory
        self.resourcesDirectory = resourcesDirectory
    }

    var asarURL: URL { appURL.appendingPathComponent("Contents/Resources/app.asar") }
    var infoPlistURL: URL { appURL.appendingPathComponent("Contents/Info.plist") }
    var configURL: URL { supportDirectory.appendingPathComponent(SupportFiles.configFileName) }
    var installedURL: URL { supportDirectory.appendingPathComponent(SupportFiles.installedFileName) }
    func backupDirectory(_ version: String) -> URL {
        supportDirectory.appendingPathComponent("backups", isDirectory: true).appendingPathComponent(version, isDirectory: true)
    }

    // -------------------------------------------------------------- Пропатчить Claude

    /// Порядок по решению 3: найти → проверить запись (промпт App Management ДО закрытия Claude)
    /// → закрыть → бэкап → патч → хэш → подпись (постоянная, не вышла — ad-hoc; #10310) → открыть Claude.
    /// `relaunch: false` — Claude после патча не открывать: его откроет вызывающий (обновление
    /// Claude из Пимпа, WF84 #7078, сперва возвращает окна по снимку).
    @discardableResult
    public func install(relaunch: Bool = true, progress: (String) -> Void = { _ in }) throws -> InstallOutcome {
        try refuseIfInsideClaude()
        let version = try appVersion()
        // Второй замок Electron 41+ (A2) — до закрытия Claude и бэкапа: откажем, прежний Claude цел.
        // Включён по известной формуле (Claude 4.29+, #11144) — digest перепишем вслед за хэшем.
        switch Patcher.asarIntegrityVerdict(framework: Patcher.electronFramework(of: appURL),
                                            integrity: Patcher.asarIntegrity(of: appURL)) {
        case .ok, .digest: break
        case .refuse(let why): throw PatchError.integrityDigestOn(version: version, why: why)
        case .unknown(let why): progress("Второй замок Electron (__asar_integrity) не проверен: \(why). Ставлю патч как обычно.")
        }
        let entitlements = try entitlementsURL()
        try ensureConfig()

        let before = try Asar.status(of: asarURL)
        progress("Claude \(version), главный сценарий \(before.mainPath), лоадер сейчас: \(before.loaderVersion > 0 ? "v\(before.loaderVersion)" : "нет")")
        progress("Настройки \(configURL.path)")

        if before.loaderVersion == Patcher.requiredLoaderVersion {
            // Лоадер есть, но прошлый прогон мог упасть между записью архива и подписью:
            // тогда хэш в Info.plist или подпись протухли, и Claude не запустится.
            let intact = infoPlistHash() == before.headerSHA256 && (!signsApp || signatureValid())
            // #10310: подпись временная, а постоянная есть — переводим (Claude перезапустится). Только по нажатию:
            // `install` зовут кнопки «Пропатчить» и обновление Claude, не таймер.
            let adhoc = livesSigning && SignIdentity.isAdhoc(appURL) == true
            let identity = !intact || adhoc ? signIdentity(progress: progress) : nil
            if intact && identity == nil {
                progress("Патч уже стоит. Обновляю только живые файлы в Application Support.")
                try installLiveFiles(progress: progress)
                try writeInstalled(version: version, headerSHA256: before.headerSHA256, mainPath: before.mainPath)
                pruneBackups()
                return .alreadyInstalled(version: version)
            }
            progress(intact ? "Перевожу подпись Claude на постоянную — доступы macOS переживут обновления."
                     : "Лоадер стоит, но хэш или подпись не сходятся — дочиню.")
            try waitForWritable(progress: progress)
            try quitClaude(progress: progress)
            try setInfoPlistHash(before.headerSHA256)
            try syncAsarIntegrityDigest(progress: progress)
            try signAndVerify(entitlements: entitlements, identity: identity, progress: progress)
            try installLiveFiles(progress: progress)
            try writeInstalled(version: version, headerSHA256: before.headerSHA256, mainPath: before.mainPath)
            pruneBackups()
            if relaunch { relaunchClaude(progress: progress) }
            return .repaired(version: version)
        }

        // Личность и проба — пока Claude открыт: окно связки ключей, если будет, не застанет его закрытым.
        let identity = signIdentity(progress: progress)
        try waitForWritable(progress: progress)
        try quitClaude(progress: progress)
        try makeBackup(version: version, loaderVersion: before.loaderVersion, progress: progress)
        progress(PatchLog.installsLoader + " в app.asar…")
        let result = try Asar.patch(asarURL)
        // Архив уже переписан: с этой секунды и до удачной подписи Claude не запускается.
        // Осечка здесь — откат из бэкапа и внятная плашка (WF45, задача #5724).
        do {
            try setInfoPlistHash(result.headerSHA256)
            try syncAsarIntegrityDigest(progress: progress)
            try signAndVerify(entitlements: entitlements, identity: identity, progress: progress)
        } catch {
            throw rollback(after: error, version: version, entitlements: entitlements, identity: identity,
                           progress: progress)
        }
        try installLiveFiles(progress: progress)
        try writeInstalled(version: version, headerSHA256: result.headerSHA256, mainPath: result.mainPath)
        pruneBackups()
        if relaunch {
            progress("Готово. " + PatchLog.opensClaude + "…")
            relaunchClaude(progress: progress)
        }
        progress("Если macOS заново спросит разрешения (микрофон, экран) — это из-за новой подписи, один раз.")
        return .installed(version: version)
    }

    /// Задача #5724. Между `Asar.patch` и удачной подписью Claude сломан: возвращаем оригиналы
    /// из бэкапа, сделанного минуту назад, и отдаём наверх ошибку, в которой сказано, что нажать.
    /// Бросать отсюда нечего — исключение возвращается вызывающему, чтобы он его бросил сам.
    func rollback(after error: Error, version: String, entitlements: URL?, identity: SignIdentity.Choice? = nil,
                  progress: (String) -> Void) -> Error {
        let why = error.humanText
        let directory = backupDirectory(version)
        let backupAsar = directory.appendingPathComponent("app.asar")
        let backupInfo = directory.appendingPathComponent("Info.plist")
        guard FileManager.default.fileExists(atPath: backupAsar.path) else {
            progress("Откатить нечем: бэкапа Claude \(version) в \(directory.path) нет.")
            return PatchError.installBroke(why: why, restored: false)
        }
        progress("Хэш или подпись не дописались — возвращаю оригинальный Claude \(version) из бэкапа…")
        do {
            try Data(contentsOf: backupAsar, options: .mappedIfSafe).write(to: asarURL, options: .atomic)
            if FileManager.default.fileExists(atPath: backupInfo.path) {
                try Data(contentsOf: backupInfo).write(to: infoPlistURL, options: .atomic)
            }
            try syncAsarIntegrityDigest(progress: progress)
        } catch {
            progress("Откат не удался: \(error.localizedDescription)")
            return PatchError.installBroke(why: why, restored: false)
        }
        // Подпись после отката — по возможности: именно она и падала. Не вышло — файлы всё равно свои.
        try? signAndVerify(entitlements: entitlements, identity: identity, progress: progress)
        progress("Оригинальные app.asar и Info.plist вернулись на место.")
        return PatchError.installBroke(why: why, restored: true)
    }

    // -------------------------------------------------------------- Снять патч

    /// Решение 8: возврат оригинальных файлов из бэкапа + переподпись (с #10310 — той же постоянной подписью, что у
    /// патча: доступы macOS переживают «Снять» и «Вернуть патч»).
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
        let identity = signIdentity(progress: progress)
        try waitForWritable(progress: progress)
        try quitClaude(progress: progress)
        progress(PatchLog.restoresOriginals + " app.asar и Info.plist \(version)…")
        try Data(contentsOf: backupAsar, options: .mappedIfSafe).write(to: asarURL, options: .atomic)
        if FileManager.default.fileExists(atPath: backupInfo.path) {
            try Data(contentsOf: backupInfo).write(to: infoPlistURL, options: .atomic)
        }
        try syncAsarIntegrityDigest(progress: progress)
        try signAndVerify(entitlements: entitlements, identity: identity, progress: progress)
        try? FileManager.default.removeItem(at: installedURL)
        progress("Готово. Подпись осталась локальной — подпись Apple вернёт только переустановка Claude. " + PatchLog.opensClaude + "…")
        relaunchClaude(progress: progress)
    }

    // -------------------------------------------------------------- Статус

    /// Быстрый статус (решение 4): версия + ElectronAsarIntegrity против installed.json.
    /// Если installed.json нет или не сходится — один разбор asar, чтобы не соврать про чужую
    /// установку (патч мог поставить старый patch-claude.mjs); удачную находку записываем.
    /// Номер лоадера в записи обязан быть нужным (WF45, задача #5722): иначе после подъёма
    /// лоадера у всей команды остался бы старый лоадер и зелёная галка «Патч стоит».
    public func state() -> ClaudeState {
        guard let version = try? appVersion() else { return .claudeNotFound }
        let recorded = installedRecord()
        let currentHash = infoPlistHash()
        if let recorded = recorded, recorded.version == version, recorded.headerSHA256 == currentHash, currentHash != nil,
           recorded.loaderVersion == Patcher.requiredLoaderVersion {
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

    /// Второй замок (#11144): digest в Electron Framework идёт за словарём ElectronAsarIntegrity из Info.plist.
    /// Звать после каждой записи Info.plist и до подписи; замок выключен — ничего не делает.
    func syncAsarIntegrityDigest(progress: (String) -> Void) throws {
        guard let integrity = Patcher.asarIntegrity(of: appURL) else { return }
        let written = try Patcher.writeAsarIntegrityDigest(framework: Patcher.electronFramework(of: appURL), integrity: integrity)
        if written > 0 { progress("Второй замок Electron: digest в Electron Framework переписан под Info.plist (срезов: \(written)).") }
    }

    // -------------------------------------------------------------- подпись

    func entitlementsURL() throws -> URL? {
        guard signsApp else { return nil }
        guard let directory = resourcesDirectory else { throw PatchError.entitlementsMissing("ресурсы приложения не найдены") }
        let url = directory.appendingPathComponent("entitlements.plist")
        guard FileManager.default.fileExists(atPath: url.path) else { throw PatchError.entitlementsMissing(url.path) }
        return url
    }

    /// Подпись Claude: личностью `identity` (#10310) — те же два прохода и `--verify`, что у временной; не вышло —
    /// как раньше, ad-hoc: патч из-за подписи не ломается.
    func signAndVerify(entitlements: URL?, identity: SignIdentity.Choice? = nil, progress: (String) -> Void) throws {
        guard signsApp, let entitlements = entitlements else { return }
        if let identity = identity {
            progress("Подписываю Claude постоянной подписью…")
            do {
                return try sign(as: identity.sha1, entitlements: entitlements, timeout: SignIdentity.signTimeout)
            } catch {
                progress("Постоянная подпись не вышла: \(error.humanText) — ставлю временную.")
            }
        }
        progress("Переподписываю Claude локальной подписью…")
        try sign(as: "-", entitlements: entitlements, timeout: 600)
    }

    private func sign(as identity: String, entitlements: URL, timeout: TimeInterval) throws {
        try Shell.run("/usr/bin/xattr", ["-cr", appURL.path])
        try Shell.run("/usr/bin/codesign", ["--force", "--deep", "--sign", identity, "--timestamp=none", appURL.path],
                      timeout: timeout)
        try Shell.run("/usr/bin/codesign", ["--force", "--sign", identity, "--timestamp=none", "--entitlements",
                                            entitlements.path, appURL.path], timeout: timeout)
        try Shell.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=2", appURL.path], timeout: timeout)
    }

    /// Живая подпись настоящего Claude, не копии в тесте: только тогда трогаем связку ключей.
    var livesSigning: Bool { signsApp && managesClaudeProcess }

    /// Личность постоянной подписи (#10310); nil — подпись будет временной. Нужной личности нет — PMP заводит свою.
    func signIdentity(progress: (String) -> Void) -> SignIdentity.Choice? {
        guard livesSigning else { return nil }
        return SignIdentity.resolve(supportDirectory: supportDirectory, create: true, progress: progress)
    }

    func signatureValid() -> Bool {
        (try? Shell.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", appURL.path])) != nil
    }

    // -------------------------------------------------------------- права на запись

    /// Первая неудачная запись в Claude.app (#9842, 12.10.2026). Окна «Разрешить» у «Управления приложениями» на новых
    /// macOS нет: система молча отказывает (в лучшем случае — уведомление, которое легко пропустить), и прежний шаг
    /// минуту ждал промпта, которого не будет. Теперь: POSIX не пускает (Claude.app чужой) — `takeOwnership` под паролем Мака; иначе это
    /// «Управление приложениями» — строка `appManagementWaitLine` (приложение по ней открывает настройки и ставит
    /// подсказку), и проба повторяется каждую секунду до `permissionWaitSeconds` или отмены (`cancelPermissionWait`).
    /// Право дали, а свой процесс всё ещё не пускают (macOS помнит отказ до перезапуска), — свежий процесс-помощник
    /// уже пишет: `needsRelaunch`, приложение перезапускается и доделывает само.
    func waitForWritable(timeout: TimeInterval = Patcher.permissionWaitSeconds, progress: (String) -> Void) throws {
        let probe = appURL.appendingPathComponent("Contents/Resources/.pimpmyclaude-write-test")
        Patcher.permissionWait.reset()
        if writeProbe(probe) == 0 { return }
        if let owner = posixBlocker() {
            // Claude.app чужой (ставил другой пользователь): промпта не будет — macOS спросит пароль своим окном,
            // и Claude станет своим. Админ не нужен: не-админу macOS предложит ввести имя и пароль администратора.
            guard managesClaudeProcess else { throw PatchError.ownershipFailed(owner: owner, why: "копию в тесте не трогаю") }
            progress(Patcher.ownershipLine(owner))
            try takeOwnership(owner: owner)
            if writeProbe(probe) == 0 { return }
        }
        progress(Patcher.appManagementWaitLine)
        let deadline = Date().addingTimeInterval(timeout)
        var helperOK = 0
        var tick = 0
        while Date() < deadline {
            if Patcher.permissionWait.cancelled { throw PatchError.cancelled }
            Thread.sleep(forTimeInterval: 1)
            if writeProbe(probe) == 0 {
                progress(PatchLog.permissionGranted + " — продолжаю.")
                return
            }
            tick += 1
            guard tick % 3 == 0 else { continue }
            helperOK = helperProbe(probe) ? helperOK + 1 : 0
            if helperOK >= 2 { throw PatchError.needsRelaunch }
        }
        throw PatchError.needsAppManagement(appPath: appURL.path, admin: currentUserIsAdmin())
    }

    /// 0 — записалось; иначе errno (EPERM — App Management, EACCES — чужой владелец).
    private func writeProbe(_ probe: URL) -> Int32 {
        let fd = open(probe.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        if fd < 0 { return errno }
        close(fd)
        unlink(probe.path)
        return 0
    }

    /// Та же проба отдельным процессом: у него свой, свежий ответ macOS о праве.
    private func helperProbe(_ probe: URL) -> Bool {
        let path = probe.path + "-helper"
        let ok = (try? Shell.run("/usr/bin/touch", [path], timeout: 10)) != nil
        if ok { unlink(path) }
        return ok
    }

    /// Кто владеет папкой, в которую POSIX не даёт писать (Contents или Contents/Resources); nil — POSIX пускает,
    /// значит мешает «Управление приложениями».
    func posixBlocker() -> String? {
        for folder in ["Contents", "Contents/Resources"] {
            var info = stat()
            let path = appURL.appendingPathComponent(folder).path
            guard stat(path, &info) == 0 else { continue }
            if Patcher.posixWritable(mode: info.st_mode, owner: info.st_uid, group: info.st_gid,
                                     uid: getuid(), groups: currentGroups()) { continue }
            return getpwuid(info.st_uid).map { String(cString: $0.pointee.pw_name) } ?? "uid \(info.st_uid)"
        }
        return nil
    }

    private func currentGroups() -> [gid_t] {
        var list = [gid_t](repeating: 0, count: 128)
        let count = getgroups(Int32(list.count), &list)
        return count > 0 ? Array(list.prefix(Int(count))) : [getgid()]
    }

    /// Сделать Claude.app своим: `chown -R` от администратора — macOS спросит пароль своим окном.
    func takeOwnership(owner: String) throws {
        // Путь и имя — аргументами скрипта, не в его тексте.
        let script = "on run argv\n do shell script \"/usr/sbin/chown -R \" & quoted form of item 1 of argv & \" \" & "
            + "quoted form of item 2 of argv with administrator privileges\nend run"
        do {
            try Shell.run("/usr/bin/osascript", ["-e", script, NSUserName(), appURL.path], timeout: 300)
        } catch {
            let why = error.humanText
            throw PatchError.ownershipFailed(owner: owner, why: why.contains("-128") ? "пароль не ввели" : why)
        }
    }

    private func currentUserIsAdmin() -> Bool {
        guard let group = getgrnam("admin") else { return false }
        return currentGroups().contains(group.pointee.gr_gid)
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

    /// `userSeconds` — сколько после принудительного выхода ждать, что Claude закроет человек (0 — сразу ошибка).
    func quitClaude(userSeconds: TimeInterval = Patcher.claudeQuitUserSeconds, progress: (String) -> Void) throws {
        guard managesClaudeProcess else { return }
        let running = runningClaude()
        guard !running.isEmpty else { return }
        progress(PatchLog.closesClaude + "…")
        running.forEach { $0.terminate() }
        if waitUntilClosed(seconds: 20) { return }
        // Шаг не молчит (#9842): Claude держит работа (идущий Claude Code, окно «Выйти?») — говорим, что дальше.
        progress("Claude не закрылся сам за 20 с — " + PatchLog.forceQuit + "…")
        runningClaude().forEach { $0.forceTerminate() }
        if waitUntilClosed(seconds: 10) { return }
        // 21.10.2026 на Маке коллеги: Claude с идущими сеансами Claude Code пережил и terminate, и forceTerminate, а
        // SIGTERM процессу закрыл его сразу — сигналы напрямую, прежде чем звать человека.
        // pid -1 у приложения без процесса: kill(-1) бьёт по всем процессам человека — только настоящие pid.
        runningClaude().map(\.processIdentifier).filter { $0 > 1 }.forEach { kill($0, SIGTERM) }
        if waitUntilClosed(seconds: 10) { return }
        runningClaude().map(\.processIdentifier).filter { $0 > 1 }.forEach { kill($0, SIGKILL) }
        if waitUntilClosed(seconds: 5) { return }
        guard userSeconds > 0 else { throw PatchError.claudeWontQuit }
        progress(Patcher.claudeQuitWaitLine)
        if waitUntilClosed(seconds: userSeconds) { return }
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

    /// Не вышло открыть — строкой в журнал (WF45, задача #5727): патч-то встал, исключение тут
    /// незачем, а молчащее «Открываю Claude…» при закрытом Claude — самое обидное место.
    func relaunchClaude(progress: (String) -> Void = { _ in }) {
        guard managesClaudeProcess else { return }
        do {
            _ = try Shell.run("/usr/bin/open", ["-a", appURL.path])
        } catch {
            let why = error.humanText
            progress("Claude открыть не удалось: \(why). Открой его сам из «Программ».")
        }
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

    /// `loaderVersion` — что сейчас лежит в главном сценарии Claude. В бэкап идёт ТОЛЬКО чистый
    /// архив (WF45, задача #5726): положить туда пропатченный — значит потом соврать в «Снять патч…»
    /// («Готово, оригинальные файлы на месте», а лоадер остался навсегда).
    func makeBackup(version: String, loaderVersion: Int, progress: (String) -> Void) throws {
        let directory = backupDirectory(version)
        let asar = directory.appendingPathComponent("app.asar")
        let info = directory.appendingPathComponent("Info.plist")
        if FileManager.default.fileExists(atPath: asar.path) && FileManager.default.fileExists(atPath: info.path) { return }
        guard loaderVersion == 0 else {
            progress("В Claude \(version) уже стоит лоадер v\(loaderVersion), а чистого бэкапа этой версии нет — "
                + "в бэкап такой архив не кладу. «Снять патч…» оригинал не вернёт: это переустановка Claude с claude.ai/download.")
            return
        }
        try SupportFiles.ensureDirectory(directory)
        progress(PatchLog.savesOriginal + " Claude \(version) в \(directory.path)…")
        try SupportFiles.write(Data(contentsOf: asarURL, options: .mappedIfSafe), to: asar)
        try SupportFiles.write(Data(contentsOf: infoPlistURL), to: info)
    }

    /// Бэкапы не копятся (ревизия WF100, z7-r02; было 7 версий, 285 МБ): после удачного патча в
    /// `backups/` остаются стоящая версия, версии наших прежних копий `Claude-<версия>.previous`
    /// рядом с Claude.app — «Снять патч…» после отката на прежнюю копию нужен её бэкап — и версии
    /// всех других копий Claude на Маке (`/Applications`, `~/Applications`; G3 WF101): патч
    /// одной копии не должен отнимать у другой «Снять патч…».
    /// Уборка — по возможности: осечка тут патч не роняет.
    func pruneBackups() {
        let fm = FileManager.default
        let root = supportDirectory.appendingPathComponent("backups", isDirectory: true)
        guard let version = try? appVersion(),
              let names = try? fm.contentsOfDirectory(atPath: root.path) else { return }
        let appName = appURL.lastPathComponent
        let stem = appURL.deletingPathExtension().lastPathComponent + "-"
        var keep: Set<String> = [version]
        for name in (try? fm.contentsOfDirectory(atPath: appURL.deletingLastPathComponent().path)) ?? []
        where ClaudeUpdater.isOwnPrevious(name, appName: appName) {
            keep.insert(String(name.dropFirst(stem.count).dropLast(ClaudeUpdater.previousSuffix.count)))
        }
        for copy in claudeCopies() {
            if let other = try? ClaudePatcher(appURL: copy, supportDirectory: supportDirectory,
                                              resourcesDirectory: nil).appVersion() {
                keep.insert(other)
            }
        }
        for name in names where !keep.contains(name) {
            var isDirectory: ObjCBool = false
            let url = root.appendingPathComponent(name, isDirectory: true)
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            try? fm.removeItem(at: url)
        }
    }

    /// claude.json создаётся значениями по умолчанию и НИКОГДА не перезаписывается.
    func ensureConfig() throws {
        try SupportFiles.ensureDirectory(supportDirectory)
        guard !FileManager.default.fileExists(atPath: configURL.path) else { return }
        let data = try JSONSerialization.data(withJSONObject: Patcher.configDefaults, options: [.prettyPrinted, .sortedKeys])
        try SupportFiles.write(data + Data("\n".utf8), to: configURL)
    }

    /// inject.js и claude.css — живые файлы лоадера; при установке обновляем на версию из сборки.
    /// Туда же ложится комплект воркфлоу (`workflow-kit` → `workflow/`): путь к WORKFLOW.md зашит
    /// в текст, который вставляет в поле ввода пункт меню «Workflow» (решение 3 плана WF9).
    func installLiveFiles(progress: (String) -> Void) throws {
        try ensureConfig()
        guard let directory = resourcesDirectory else { return }
        let inject = directory.appendingPathComponent(SupportFiles.injectFileName)
        if FileManager.default.fileExists(atPath: inject.path) {
            let target = supportDirectory.appendingPathComponent(SupportFiles.injectFileName)
            let bundled = try Data(contentsOf: inject)
            let liveText = try? String(contentsOf: target, encoding: .utf8)
            if let bundledText = String(data: bundled, encoding: .utf8),
               Patcher.injectKeepsLive(bundled: bundledText, live: liveText) {
                progress("Живая страница новее, чем в сборке, — оставил её.")
            } else {
                try SupportFiles.write(bundled, to: target)
            }
        }
        try installLiveCSS(from: directory, progress: progress)
        try installWorkflowKit(from: directory)
        progress("Живые файлы в \(supportDirectory.path) обновлены.")
    }

    /// claude.css человек правит сам (`docs/TEAM.md` прямо предлагает дописывать свои правила
    /// выше или ниже авто-блока), поэтому файл из бандла НЕ кладётся поверх (WF45, задача #5723):
    /// из него берётся только блок между маркерами, остальное живого файла сохраняется дословно.
    func installLiveCSS(from resources: URL, progress: (String) -> Void) throws {
        let source = resources.appendingPathComponent(Patcher.cssFileName)
        guard let bundled = try? String(contentsOf: source, encoding: .utf8) else { return }
        let target = supportDirectory.appendingPathComponent(Patcher.cssFileName)
        let live = try? String(contentsOf: target, encoding: .utf8)
        let merged = Patcher.mergeCSS(bundled: bundled, live: live)
        guard merged != live else { return }
        try SupportFiles.write(Data(merged.utf8), to: target)
        if live != nil { progress("В claude.css обновил только блок PimpMyClaude — свои правила остались на месте.") }
    }

    /// Комплекта в сборке нет (старый бандл) — молча пропускаем: пункт меню положит его сам.
    func installWorkflowKit(from resources: URL) throws {
        try Patcher.installWorkflowKit(from: resources, to: supportDirectory)
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
        // Поля нет — запись древняя, номер лоадера неизвестен: 0 отправит статус разбирать asar,
        // а тот запишет правду обратно (WF45, задача #5722). Считать её «нужной версией» нельзя.
        return InstalledRecord(version: version, headerSHA256: hash, loaderVersion: json["loaderVersion"] as? Int ?? 0)
    }

    func writeInstalled(version: String, headerSHA256: String, mainPath: String) throws {
        try SupportFiles.ensureDirectory(supportDirectory)
        let record: [String: Any] = [
            "appPath": appURL.path,
            "version": version,
            "headerSHA256": headerSHA256,
            "loaderVersion": Patcher.requiredLoaderVersion,
            "mainPath": mainPath,
            "at": ISO8601DateFormatter().string(from: Date()),
        ]
        let data = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
        try SupportFiles.write(data, to: installedURL)
    }
}

extension Patcher {
    /// Обновили Пимп поверх старого (ревизия WF100, z9-r01; критик WF101, C5 и C18): живой inject.js
    /// кладёт только «Пропатчить Claude», и у команды с 1.5.2 на 1.8.x осталась бы страница wf70 без
    /// Авто-Allow. Зовётся ОДИН раз за запуск, синхронно, до `ax.start()`: страница из бандла СТРОГО
    /// новее живой — кладём её и комплект workflow/. claude.css не трогаем. Живой нет, редакция
    /// не читается хоть у одной или живая равна/новее (#7035) — ничего. Лоадер перечитает по mtime.
    @discardableResult
    public static func refreshLiveFilesIfBundledNewer(supportDirectory: URL = defaultSupportDirectory,
                                                      resourcesDirectory: URL? = bundledResourcesDirectory) -> Bool {
        guard let resources = resourcesDirectory else { return false }
        let target = supportDirectory.appendingPathComponent(SupportFiles.injectFileName)
        guard let bundled = try? Data(contentsOf: resources.appendingPathComponent(SupportFiles.injectFileName)),
              let bundledVersion = injectVersion(of: String(decoding: bundled, as: UTF8.self)),
              let live = try? String(contentsOf: target, encoding: .utf8),
              let liveVersion = injectVersion(of: live),
              bundledVersion > liveVersion else { return false }
        do { try SupportFiles.write(bundled, to: target) } catch {
            NSLog("PimpMyClaude: страница из сборки не легла: \(error.localizedDescription)")
            return false
        }
        do { try installWorkflowKit(from: resources, to: supportDirectory) } catch {
            NSLog("PimpMyClaude: комплект workflow из сборки не лёг: \(error.localizedDescription)")
        }
        return true
    }

    static func installWorkflowKit(from resources: URL, to supportDirectory: URL) throws {
        try copyWorkflowKit(from: resources.appendingPathComponent(Patcher.workflowKitDirName, isDirectory: true),
                            to: supportDirectory.appendingPathComponent(Patcher.workflowDirName, isDirectory: true))
    }

    /// Файлы комплекта (`workflow-kit` бандла) в папку `workflow`; комплекта нет или он пуст — молча ничего.
    /// Одна копия на патчер и пункт «🚀 Workflow» (`WorkflowKit.install`).
    public static func copyWorkflowKit(from source: URL, to target: URL) throws {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: source.path), !names.isEmpty else { return }
        try SupportFiles.ensureDirectory(target)
        for name in names.sorted() where !name.hasPrefix(".") {
            try SupportFiles.write(Data(contentsOf: source.appendingPathComponent(name)), to: target.appendingPathComponent(name))
        }
    }
}

// ------------------------------------------------------------------ подпроцессы и процессы

/// Флаг отмены между ниткой патча и главной: взвёл — нитка увидит на следующем шаге.
final class CancelFlag {
    private let lock = NSLock()
    private var value = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func cancel() { lock.lock(); value = true; lock.unlock() }
    func reset() { lock.lock(); value = false; lock.unlock() }
}

enum Shell {
    /// Утилита не дольше `timeout` — общим запуском `SelfUpdater.run` (stdout и stderr в одну трубу; не уложилась —
    /// погашена). Раньше ждали без срока (находка R9 проверки 10.10.2026): зависший hdiutil, codesign или spctl
    /// держал «занято» вечно. Десять минут — с запасом на самое долгое, переподпись и образ Claude.
    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval = 600) throws -> String {
        let name = (launchPath as NSString).lastPathComponent
        guard let run = SelfUpdater.run(launchPath, arguments, timeout: timeout) else {
            throw PatchError.tool(name: name, output: "не запустилась или не уложилась в \(Int(timeout)) с")
        }
        guard run.status == 0 else {
            throw PatchError.tool(name: name, output: run.output.isEmpty ? "код \(run.status)" : run.output)
        }
        return run.output
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
