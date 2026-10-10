import CryptoKit
import Foundation
import CoreFoundation

// Обновление Claude из Пимпа (WF84, задачи #7078 и #7079). Пропатченный Claude сам обновиться не
// может: Squirrel сверяет подпись нового бандла с требованием, снятым с работающего, а наш бандл
// подписан ad-hoc (docs/DECISIONS.md). Поэтому Пимп ставит новую версию сам, мимо Squirrel:
//   1. `check()` — манифест зеркала (R2, запасной — GitHub API) и официальный редирект Anthropic на
//      DMG (без device_id); ответ — самая новая версия, «последняя» — только когда ответили все.
//   2. `prepare(_:)` — Claude ЕЩЁ РАБОТАЕТ: архив скачан гонкой источников (`ClaudeDownloadRace`),
//      размер и sha256 сошлись, подпись DMG проверена до монтирования, бандл распакован рядом с живым
//      под скрытым именем, подпись Anthropic, Gatekeeper, bundle id и версия проверены, рядом лёг
//      `ready.json` — готовность переживает перезапуск Пимпа. Любая осечка не меняет установленный Claude.
//   3. `install(_:relaunch:)` — только теперь Claude закрывается; подмена двумя переименованиями
//      в пределах одной папки; прежний бандл остаётся ОДНОЙ копией под именем без `.app`
//      (Launch Services её не зарегистрирует, `Patcher.locateClaude` её не увидит); дальше патч
//      `ClaudePatcher.install(relaunch:)`. Подмена или патч сорвались — прежний бандл возвращается.
// Скрытые `/Applications/.Claude-*` (старые копии Элвиса) этот код не трогает ни при каких именах.
// Выход в сеть — по слову Элвиса в #7078 («обнови сам»), критик WF84 п.15.

/// Релиз из фида: что качать и чем проверить.
/// `sha256` пустой и `size` 0 — не известны (официальный редирект их не даёт): тогда опора на
/// Content-Length, подпись Anthropic и версию из бандла.
public struct ClaudeRelease: Equatable {
    public enum Format: String { case zip, dmg }
    public let version: String
    public let url: URL
    public let sha256: String
    public let size: Int64
    public let format: Format
    /// Только копии того же файла: общие sha256 и размер.
    public let mirrors: [URL]
    /// Другой формат имеет собственные метаданные и проверяется отдельно.
    public let fallbacks: [ClaudeRelease]

    public init(version: String, url: URL, sha256: String, size: Int64,
                format: Format = .zip, mirrors: [URL] = [], fallbacks: [ClaudeRelease] = []) {
        self.version = version
        self.url = url
        self.sha256 = sha256.lowercased()
        self.size = size
        self.format = format
        self.mirrors = mirrors
        self.fallbacks = fallbacks
    }
}

/// Ответ фида относительно стоящей версии.
public enum ClaudeFeedAnswer: Equatable {
    /// Новее нет — «У тебя последняя версия Claude». `feed` может быть и старше стоящей.
    case latest(installed: String, feed: String)
    case available(installed: String, release: ClaudeRelease)
}

/// Скачанный и проверенный бандл, готовый к подмене. Claude пока не тронут.
public struct PreparedClaudeUpdate {
    public let release: ClaudeRelease
    public let installedVersion: String
    /// Проверенный `Claude.app` во временной скрытой папке рядом с живым (тот же том — подмена
    /// переименованием).
    public let stagedApp: URL

    public init(release: ClaudeRelease, installedVersion: String, stagedApp: URL) {
        self.release = release
        self.installedVersion = installedVersion
        self.stagedApp = stagedApp
    }
}

/// Можно ли качать в фоне (критик WF87 п. 9). Не `ok` — фон молчит, ручное обновление остаётся.
public enum ClaudeUpdatePreflight: Equatable {
    case ok
    /// В папку Claude писать нельзя (нет прав админа) — обновить можно только вручную.
    case notWritable(String)
    /// Мало места: нужно столько байт, свободно столько.
    case noSpace(needed: Int64, free: Int64)
}

public struct ClaudeUpdateOutcome {
    public let from: String
    public let to: String
    public let patch: InstallOutcome
    /// Где лежит прежний бандл (единственная копия, имя без `.app`).
    public let previous: URL
}

public enum ClaudeUpdateError: LocalizedError {
    case feed(String)
    case cancelled
    case notNewer(installed: String, offered: String)
    case download(String)
    case sizeMismatch(expected: Int64, got: Int64)
    case checksumMismatch
    case badArchive(String)
    case wrongBundle(String)
    case signature(String)
    case changedMeanwhile(String)
    case swapFailed(why: String, restored: Bool, previous: String)
    case patchFailed(why: String, restored: Bool, previous: String)
    /// Второй замок Electron 41+ включён в новом Claude (A2): патч на него не ляжет — не ставим.
    case integrityRefused(version: String, why: String)
    /// Перезапуск без обновления (`restart-claude`, WF108) не удался — причина строкой.
    case restartFailed(String)

    public var errorDescription: String? {
        switch self {
        case .restartFailed(let why):
            return why
        case .feed(let why):
            return "Не узнал, есть ли новая версия Claude: \(why)"
        case .cancelled:
            return "Загрузку Claude отменили. Claude не тронут."
        case .notNewer(let installed, let offered):
            return "Обновлять не на что: стоит Claude \(installed), в фиде \(offered)."
        case .download(let why):
            return "Архив Claude не скачался: \(why). Claude не тронут."
        case .sizeMismatch(let expected, let got):
            return "Архив Claude не того размера (\(got) байт, ждали \(expected)). Claude не тронут."
        case .checksumMismatch:
            return "Контрольная сумма архива Claude не сошлась с фидом. Claude не тронут."
        case .badArchive(let why):
            return "Архив Claude не распаковался: \(why). Claude не тронут."
        case .wrongBundle(let why):
            return "В архиве не тот Claude: \(why). Claude не тронут."
        case .signature(let why):
            return "Подпись нового Claude не прошла проверку: \(why). Claude не тронут."
        case .changedMeanwhile(let why):
            return "Пока шла проверка, Claude поменялся: \(why). Нажми «Обновить Claude» ещё раз."
        case .swapFailed(let why, let restored, let previous):
            return restored
                ? "Новый Claude не встал на место: \(why). Прежний Claude вернулся — он запускается."
                : "Новый Claude не встал на место: \(why). Прежний Claude лежит в \(previous) — переименуй его обратно в Claude.app."
        case .patchFailed(let why, let restored, let previous):
            return restored
                ? "Новый Claude встал, но патч на него не лёг: \(why). Вернул прежний Claude с патчем — всё как было."
                : "Новый Claude встал, но патч на него не лёг: \(why). Прежний Claude лежит в \(previous)."
        case .integrityRefused(let version, let why):
            return "Claude \(version) Пимп пока не патчит: \(why). Стоящий Claude не тронут, эту версию больше не качаю."
        }
    }
}

public struct ClaudeUpdater {
    /// Team ID Anthropic PBC в сертификате Developer ID (снято с подписанного Anthropic бандла 23.09.2026).
    public static let anthropicTeamID = "Q6L2SF6YDW"
    public static let mirrorFeed = URL(string: "https://api.github.com/repos/Wangnov/claude-app-mirror/releases/latest")!
    public static let fastMirror = URL(string: "https://claudeapp.agentsmirror.com/latest/mac")!
    /// Манифест R2 рядом с `latest/mac`: версия, sha256 и размер без GitHub API (лимит 60 запросов/ч на IP).
    public static let mirrorManifest = URL(string: "https://claudeapp.agentsmirror.com/latest/manifest")!
    /// Официальный редирект Anthropic на DMG: без device_id и версии, 307 на
    /// `downloads.claude.ai/releases/darwin/universal/<версия>/Claude-<hash>.dmg`.
    public static let officialRedirect = URL(string: "https://api.anthropic.com/api/desktop/darwin/universal/dmg/latest/redirect")!
    /// Закреплённый файл версии на GitHub — тот же DMG, что у R2.
    public static func githubPinned(_ version: String) -> URL {
        URL(string: "https://github.com/Wangnov/claude-app-mirror/releases/download/claude-app-v\(version)/Claude-mac-universal.dmg")!
    }
    /// Потолок фоновой гонки (критик WF87 п. 5): общего лимита на запрос нет.
    public static let backgroundDeadline: TimeInterval = 2 * 60 * 60
    /// Файл готовности в папке распаковки.
    public static let readyFileName = "ready.json"
    /// Скрытая папка распаковки рядом с живым бандлом. Имя НЕ `.Claude-…`: такие папки — чужие.
    public static let stagingDirName = ".pimpmyclaude-claude-update"
    /// Прежний бандл: `Claude-<версия>.previous` — без `.app`, чтобы macOS не видела в нём программу.
    public static let previousSuffix = ".previous"
    /// Версии, которые Пимп отказался ставить из-за второго замка (A2):
    /// `{"pimpBuild": "<CFBundleVersion Пимпа>", "versions": {"<версия>": "<причина>"}}` в папке
    /// загрузки — чтобы фон не качал их заново каждый день. Отказ помнит сборку Пимпа (G2 WF101):
    /// новая сборка могла научиться патчить такой Claude, и чужой файл для неё не действует.
    public static let refusedFileName = "refused.json"
    /// Сборка Пимпа, в которой идёт проверка: `CFBundleVersion` приложения.
    public static var currentPimpBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    }

    public var appURL: URL
    public var supportDirectory: URL
    public var resourcesDirectory: URL?
    /// Third-party feeds and archives require an explicit policy, including manual retries.
    public var allowMirrors: Bool
    /// Как у `ClaudePatcher`: тест гоняет весь путь на копии — не подписывать и Claude не трогать.
    public var signsApp = true
    public var managesClaudeProcess = true
    /// Проверки подписи Anthropic и Gatekeeper. Выключает только тест: поддельный бандл не подписан.
    public var checksSignature = true
    /// Правила гонки загрузки; `deadline` фона — `backgroundDeadline`.
    public var raceRules = ClaudeDownloadRace.Rules()
    /// Сборка Пимпа для `refused.json`; тест подменяет, чтобы показать смену сборки.
    public var pimpBuild = ClaudeUpdater.currentPimpBuild
    // Подмены транспорта для тестов: та же проверка архивов, без выхода в сеть.
    var fetchMetadata: (URL, TimeInterval) throws -> Data = ClaudeUpdater.fetch
    var resolveRedirect: (URL, TimeInterval) throws -> URL = ClaudeUpdater.redirectTarget
    var raceConfiguration: () -> URLSessionConfiguration = { .ephemeral }

    public init(appURL: URL,
                supportDirectory: URL = Patcher.defaultSupportDirectory,
                resourcesDirectory: URL? = Patcher.bundledResourcesDirectory,
                allowMirrors: Bool = false) {
        self.appURL = appURL
        self.supportDirectory = supportDirectory
        self.resourcesDirectory = resourcesDirectory
        self.allowMirrors = allowMirrors
    }

    var parentDirectory: URL { appURL.deletingLastPathComponent() }
    var stagingDirectory: URL { parentDirectory.appendingPathComponent(Self.stagingDirName, isDirectory: true) }
    var downloadDirectory: URL { supportDirectory.appendingPathComponent("claude-update", isDirectory: true) }
    func archiveURL(_ release: ClaudeRelease) -> URL {
        downloadDirectory.appendingPathComponent("Claude-\(release.version).\(release.format.rawValue)")
    }

    /// Патчер на тот же бандл и с теми же подменами (закрыть, открыть, подписать).
    func patcher(for url: URL? = nil) -> ClaudePatcher {
        var patcher = ClaudePatcher(appURL: url ?? appURL, supportDirectory: supportDirectory, resourcesDirectory: resourcesDirectory)
        patcher.signsApp = signsApp
        patcher.managesClaudeProcess = managesClaudeProcess
        return patcher
    }

    public func installedVersion() throws -> String { try patcher().appVersion() }

    // -------------------------------------------------------------- чистые правила (под тестом)

    /// Версии числами по частям: `2.2553.13` > `2.2553.2`; недостающая часть — 0. Не число — nil.
    public static func compareVersions(_ a: String, _ b: String) -> ComparisonResult? {
        func parts(_ text: String) -> [Int]? {
            let pieces = text.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
            guard !pieces.isEmpty else { return nil }
            var numbers: [Int] = []
            for piece in pieces {
                guard !piece.isEmpty, piece.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(piece) else { return nil }
                numbers.append(n)
            }
            return numbers
        }
        guard let left = parts(a), let right = parts(b) else { return nil }
        for i in 0..<max(left.count, right.count) {
            let l = i < left.count ? left[i] : 0
            let r = i < right.count ? right[i] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    /// GitHub stable release: точный macOS asset и закреплённый URL, без Windows/prerelease.
    public static func parseMirrorFeed(_ data: Data) throws -> ClaudeRelease {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              json["draft"] as? Bool == false, json["prerelease"] as? Bool == false,
              let tag = json["tag_name"] as? String, tag.hasPrefix("claude-app-v") else {
            throw ClaudeUpdateError.feed("зеркало не вернуло стабильный релиз")
        }
        let version = String(tag.dropFirst("claude-app-v".count))
        guard version == version.trimmingCharacters(in: .whitespacesAndNewlines),
              compareVersions(version, version) != nil,
              let assets = json["assets"] as? [[String: Any]] else {
            throw ClaudeUpdateError.feed("у зеркала нет версии или файлов")
        }
        let assetsForMac = assets.filter { $0["name"] as? String == "Claude-mac-universal.dmg" }
        let pinned = "https://github.com/Wangnov/claude-app-mirror/releases/download/\(tag)/Claude-mac-universal.dmg"
        guard assetsForMac.count == 1, let asset = assetsForMac.first,
              asset["state"] as? String == "uploaded",
              asset["browser_download_url"] as? String == pinned,
              let digest = asset["digest"] as? String, digest.hasPrefix("sha256:"),
              let size = asset["size"] as? NSNumber, CFGetTypeID(size) != CFBooleanGetTypeID(),
              size.int64Value > 0, size.doubleValue == Double(size.int64Value) else {
            throw ClaudeUpdateError.feed("у зеркала нет проверяемого macOS DMG")
        }
        let sha = String(digest.dropFirst(7))
        guard sha.count == 64, sha.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            throw ClaudeUpdateError.feed("у зеркала нет sha256")
        }
        return ClaudeRelease(version: version, url: fastMirror, sha256: sha, size: size.int64Value,
                             format: .dmg, mirrors: [URL(string: pinned)!])
    }

    /// Манифест R2 (`latest/manifest`): macOS universal DMG — версия, sha256, размер. Файл тот же у R2
    /// `latest/mac`, у GitHub по тегу версии и у Anthropic по `url` манифеста — три копии одного DMG.
    public static func parseMirrorManifest(_ data: Data) throws -> ClaudeRelease {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let sources = json["sources"] as? [String: Any],
              let macos = sources["macos"] as? [String: Any],
              let mac = macos["universal"] as? [String: Any],
              mac["format"] as? String == "dmg",
              let version = mac["version"] as? String, compareVersions(version, version) != nil,
              let sha = (mac["sha256"] as? String)?.lowercased(), sha.count == 64,
              sha.allSatisfy({ $0.isASCII && $0.isHexDigit }),
              let size = mac["contentLength"] as? NSNumber, CFGetTypeID(size) != CFBooleanGetTypeID(),
              size.int64Value > 0, size.doubleValue == Double(size.int64Value) else {
            throw ClaudeUpdateError.feed("в манифесте зеркала нет проверяемого macOS DMG")
        }
        var mirrors = [githubPinned(version)]
        if let link = mac["url"] as? String, let url = URL(string: link),
           (try? parseOfficialRedirect(url))?.version == version {
            mirrors.append(url)
        }
        return ClaudeRelease(version: version, url: fastMirror, sha256: sha, size: size.int64Value,
                             format: .dmg, mirrors: mirrors)
    }

    /// Цель официального редиректа: `https://downloads.claude.ai/releases/darwin/universal/<версия>/<файл>.dmg`.
    /// sha256 и размера нет — их проверят Content-Length, подпись Anthropic и версия из бандла.
    public static func parseOfficialRedirect(_ location: URL) throws -> ClaudeRelease {
        let parts = location.pathComponents
        guard location.scheme == "https", location.host == "downloads.claude.ai", parts.count == 6,
              parts[1] == "releases", parts[2] == "darwin", parts[3] == "universal",
              compareVersions(parts[4], parts[4]) != nil, parts[5].hasSuffix(".dmg") else {
            throw ClaudeUpdateError.feed("редирект Anthropic ведёт не на DMG Claude (\(location.absoluteString))")
        }
        return ClaudeRelease(version: parts[4], url: location, sha256: "", size: 0, format: .dmg)
    }

    /// Самый новый из ответивших. Второй — запасной (критик WF87 п. 6): той же версии он встаёт в
    /// гонку полосой, старше — выручит, если новый не скачался и он всё ещё новее стоящего.
    static func preferredRelease(mirror: ClaudeRelease?, official: ClaudeRelease?) throws -> ClaudeRelease {
        guard let mirror = mirror else {
            guard let official = official else { throw ClaudeUpdateError.feed("оба источника недоступны") }
            return official
        }
        guard let official = official else { return mirror }
        let (first, second) = compareVersions(official.version, mirror.version) == .orderedDescending
            ? (official, mirror) : (mirror, official)
        return ClaudeRelease(version: first.version, url: first.url, sha256: first.sha256, size: first.size,
                             format: first.format, mirrors: first.mirrors, fallbacks: [second])
    }

    /// Ответ проверки. Новее стоящего хоть у кого — `available`; «последняя» — только когда ответили
    /// ОБА источника (критик WF87, #7639): недоступность — «не узнал», а не «последняя».
    static func combine(installed: String, mirror: Result<ClaudeRelease, Error>,
                        official: Result<ClaudeRelease, Error>) throws -> ClaudeFeedAnswer {
        var missing: [String] = []
        if case .failure(let error) = mirror { missing.append("зеркало — " + reason(error)) }
        if case .failure(let error) = official { missing.append("Anthropic — " + reason(error)) }
        guard let best = try? preferredRelease(mirror: try? mirror.get(), official: try? official.get()) else {
            throw ClaudeUpdateError.feed(missing.joined(separator: "; "))
        }
        if compareVersions(best.version, installed) == .orderedDescending {
            return .available(installed: installed, release: best)
        }
        guard missing.isEmpty else { throw ClaudeUpdateError.feed(missing.joined(separator: "; ")) }
        return .latest(installed: installed, feed: best.version)
    }

    /// Имя прежнего бандла: `Claude.app` 2.2553.13 → `Claude-2.2553.13.previous`.
    public static func previousName(appName: String, version: String) -> String {
        "\((appName as NSString).deletingPathExtension)-\(version)\(previousSuffix)"
    }

    /// Наша прежняя копия (её и только её можно убирать): `Claude-<что угодно>.previous`.
    /// `.Claude-…` сюда не попадает никогда — имя обязано начинаться с имени бандла без точки.
    public static func isOwnPrevious(_ name: String, appName: String) -> Bool {
        let stem = (appName as NSString).deletingPathExtension
        return !stem.isEmpty && !stem.hasPrefix(".") && name.hasPrefix(stem + "-") && name.hasSuffix(previousSuffix)
    }

    /// Требование к подписи: bundle id Claude и сертификат Developer ID команды Anthropic.
    public static func signatureRequirement(bundleID: String = Patcher.claudeBundleID, teamID: String = anthropicTeamID) -> String {
        "identifier \"\(bundleID)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
    }

    /// Требование к подписи образа DMG: Developer ID Anthropic (идентификатор образа меняется с версией).
    public static func imageRequirement(teamID: String = anthropicTeamID) -> String {
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
    }

    // -------------------------------------------------------------- 1. фид

    /// Два-три коротких запроса с таймаутом: манифест R2 (не ответил — GitHub API) и официальный
    /// редирект без идентификаторов. Недоступность одного не блокирует другой.
    public func check(timeout: TimeInterval = 10) throws -> ClaudeFeedAnswer {
        let installed = try installedVersion()
        if !allowMirrors {
            let official = try Self.parseOfficialRedirect(resolveRedirect(Self.officialRedirect, timeout))
            return Self.compareVersions(official.version, installed) == .orderedDescending
                ? .available(installed: installed, release: official) : .latest(installed: installed, feed: official.version)
        }
        let mirror = Result { try mirrorRelease(timeout: timeout) }
        let official = Result { try Self.parseOfficialRedirect(resolveRedirect(Self.officialRedirect, timeout)) }
        return try Self.combine(installed: installed, mirror: mirror, official: official)
    }

    func mirrorRelease(timeout: TimeInterval) throws -> ClaudeRelease {
        do {
            return try Self.parseMirrorManifest(fetchMetadata(Self.mirrorManifest, timeout))
        } catch let manifest {
            do { return try Self.parseMirrorFeed(fetchMetadata(Self.mirrorFeed, timeout)) }
            catch { throw ClaudeUpdateError.feed("R2: \(Self.reason(manifest)); GitHub: \(Self.reason(error))") }
        }
    }

    // -------------------------------------------------------------- 2. скачать и проверить (Claude работает)

    /// Всё, что может сорваться, — здесь, пока Claude открыт и чаты живы. Живой бандл не меняется.
    /// Версии по убыванию: гонка всех источников самой новой; не вышло — следующая версия, если она
    /// всё ещё новее стоящей (критик WF87 п. 6). `control` — снимки гонки для UI и отмена.
    public func prepare(_ release: ClaudeRelease, control: DownloadControl? = nil,
                        progress: (String) -> Void = { _ in }) throws -> PreparedClaudeUpdate {
        let installed = try installedVersion()
        guard Self.compareVersions(release.version, installed) == .orderedDescending else {
            throw ClaudeUpdateError.notNewer(installed: installed, offered: release.version)
        }
        var lastError: Error = ClaudeUpdateError.download("нет доступных источников")
        let refused = refusedVersions()
        for group in Self.versionGroups(release).map({ Self.allowedReleases($0, allowMirrors: allowMirrors) }).filter({ !$0.isEmpty })
        where Self.compareVersions(group[0].version, installed) == .orderedDescending {
            if control?.isCancelled == true { throw ClaudeUpdateError.cancelled }
            if let why = refused[group[0].version] {
                lastError = ClaudeUpdateError.integrityRefused(version: group[0].version, why: why)
                progress(Self.describe(lastError))
                continue
            }
            do {
                return try prepareVersion(group, installed: installed, control: control, progress: progress)
            } catch ClaudeUpdateError.cancelled {
                throw ClaudeUpdateError.cancelled
            } catch {
                lastError = error
                progress(Self.describe(error))
            }
        }
        throw lastError
    }

    /// Релиз и запасные, собранные по версиям, новые первыми.
    static func versionGroups(_ release: ClaudeRelease) -> [[ClaudeRelease]] {
        var groups: [[ClaudeRelease]] = []
        for candidate in [release] + release.fallbacks {
            if let index = groups.firstIndex(where: { compareVersions($0[0].version, candidate.version) == .orderedSame }) {
                groups[index].append(candidate)
            } else {
                groups.append([candidate])
            }
        }
        return groups.sorted { compareVersions($0[0].version, $1[0].version) == .orderedDescending }
    }

    /// Полосы гонки одной версии: у каждой свои размер и sha256; один адрес — одна полоса (с
    /// известным sha256 важнее).
    static func sources(_ group: [ClaudeRelease], allowMirrors: Bool = true) -> [DownloadSource] {
        var result: [DownloadSource] = []
        for release in group {
            for url in [release.url] + release.mirrors where allowedSource(url, allowMirrors: allowMirrors) {
                let source = DownloadSource(id: sourceID(url), title: sourceTitle(url), url: url,
                                            expectedSize: release.size, sha256: release.sha256, format: release.format)
                if let index = result.firstIndex(where: { $0.url == url }) {
                    if result[index].sha256 == nil, source.sha256 != nil { result[index] = source }
                } else {
                    result.append(source)
                }
            }
        }
        return result
    }

    static func allowedSource(_ url: URL, allowMirrors: Bool) -> Bool {
        // Local archives are the existing test/offline path and never contact a third party.
        if url.isFileURL { return true }
        if allowMirrors { return true }
        guard url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return false }
        return (try? parseOfficialRedirect(url)) != nil
    }

    static func allowedReleases(_ group: [ClaudeRelease], allowMirrors: Bool) -> [ClaudeRelease] {
        group.compactMap { release in
            let urls = ([release.url] + release.mirrors).filter { allowedSource($0, allowMirrors: allowMirrors) }
            guard let first = urls.first else { return nil }
            return ClaudeRelease(version: release.version, url: first, sha256: release.sha256, size: release.size,
                                 format: release.format, mirrors: Array(urls.dropFirst()))
        }
    }

    /// Имя источника для людей: «R2», «GitHub», «Anthropic», «файл».
    public static func sourceTitle(_ url: URL) -> String {
        if url.isFileURL { return "файл" }
        switch url.host ?? "" {
        case "claudeapp.agentsmirror.com": return "R2"
        case "github.com", "objects.githubusercontent.com": return "GitHub"
        case "downloads.claude.ai", "api.anthropic.com": return "Anthropic"
        case let host: return host.isEmpty ? url.absoluteString : host
        }
    }

    static func sourceID(_ url: URL) -> String {
        switch sourceTitle(url) {
        case "R2": return "r2"
        case "GitHub": return "github"
        case "Anthropic": return "anthropic"
        case "файл": return "file"
        case let other: return other
        }
    }

    private func prepareVersion(_ group: [ClaudeRelease], installed: String, control: DownloadControl?,
                                progress: (String) -> Void) throws -> PreparedClaudeUpdate {
        let fm = FileManager.default
        try fm.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        // Держим архивы только этой версии: старые из прошлых попыток и недокачанные гонки убираем.
        let keep = Set(group.map { archiveURL($0).lastPathComponent })
        for name in (try? fm.contentsOfDirectory(atPath: downloadDirectory.path)) ?? []
        where (name.hasPrefix("Claude-") && (name.hasSuffix(".zip") || name.hasSuffix(".dmg")) && !keep.contains(name))
            || name.hasPrefix("race-") {
            try? fm.removeItem(at: downloadDirectory.appendingPathComponent(name))
        }
        var excluded: [URL] = []
        var verifyError: Error?
        while true {
            if control?.isCancelled == true { throw ClaudeUpdateError.cancelled }
            let got: (release: ClaudeRelease, archive: URL, source: URL?)
            do {
                got = try obtainArchive(group, excluding: excluded, control: control, progress: progress)
            } catch {
                if case ClaudeUpdateError.cancelled = error { throw error }
                throw verifyError ?? error
            }
            do {
                return try unpackAndVerify(got.archive, release: got.release, installed: installed, progress: progress)
            } catch ClaudeUpdateError.integrityRefused(let version, let why) {
                // Не источник виноват — сама версия: другие зеркала не качаем, архив не держим.
                try? fm.removeItem(at: got.archive)
                throw ClaudeUpdateError.integrityRefused(version: version, why: why)
            } catch {
                // Архив сошёлся, а бандл не тот (подпись, версия): этот источник больше не берём.
                try? fm.removeItem(at: got.archive)
                verifyError = error
                progress(Self.describe(error))
                if let source = got.source { excluded.append(source) }
            }
        }
    }

    /// Готовый архив с верной суммой — без сети; иначе гонка неотброшенных источников.
    private func obtainArchive(_ group: [ClaudeRelease], excluding: [URL], control: DownloadControl?,
                               progress: (String) -> Void) throws -> (release: ClaudeRelease, archive: URL, source: URL?) {
        let fm = FileManager.default
        for release in group where !release.sha256.isEmpty {
            let archive = archiveURL(release)
            if fm.fileExists(atPath: archive.path), (try? checkArchive(archive, release)) != nil {
                progress("Архив Claude \(release.version) уже скачан и сходится с фидом.")
                return (release, archive, nil)
            }
        }
        let sources = Self.sources(group, allowMirrors: allowMirrors).filter { !excluding.contains($0.url) }
        guard !sources.isEmpty else { throw ClaudeUpdateError.download("источников больше нет") }
        let version = group[0].version
        let size = group.map { $0.size }.max() ?? 0
        progress("Качаю Claude \(version)" + (size > 0 ? " (\(size / 1_000_000) МБ)…" : "…"))
        let raceDirectory = downloadDirectory.appendingPathComponent("race-\(version)", isDirectory: true)
        defer { try? fm.removeItem(at: raceDirectory) }
        let race = ClaudeDownloadRace(sources: sources, directory: raceDirectory, rules: raceRules,
                                      configuration: raceConfiguration())
        race.allowsRedirect = { Self.allowedSource($0, allowMirrors: allowMirrors) }
        race.onSnapshot = control?.onSnapshot
        let winner: RaceWinner = try withoutActuallyEscaping(progress) { log in
            race.log = log
            defer { race.log = nil }
            control?.attach(race)
            return try race.run()
        }
        let source = winner.source
        let release = ClaudeRelease(version: version, url: source.url, sha256: source.sha256 ?? "",
                                    size: source.expectedSize ?? 0, format: source.format)
        let archive = archiveURL(release)
        try? fm.removeItem(at: archive)
        do { try fm.moveItem(at: winner.file, to: archive) }
        catch { throw ClaudeUpdateError.download("не переложить архив: \(Self.describe(error))") }
        progress("Архив скачан (\(source.title))" + (source.sha256 != nil ? ", размер и sha256 сошлись." : "."))
        return (release, archive, source.url)
    }

    private func unpackAndVerify(_ archive: URL, release: ClaudeRelease, installed: String,
                                 progress: (String) -> Void) throws -> PreparedClaudeUpdate {
        let fm = FileManager.default
        if release.format == .dmg, checksSignature {
            // Образ подписан и нотаризован Anthropic (проверено 25.09.2026): чужой не монтируем вовсе.
            do { try Shell.run("/usr/bin/codesign", ["--verify", "-R=" + Self.imageRequirement(), archive.path]) }
            catch { throw ClaudeUpdateError.signature("образ DMG: \(Self.describe(error))") }
        }
        progress("Распаковываю…")
        try? fm.removeItem(at: stagingDirectory)
        try fm.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        do {
            switch release.format {
            case .zip: try Shell.run("/usr/bin/ditto", ["-x", "-k", archive.path, stagingDirectory.path])
            case .dmg: try unpackDMG(archive)
            }
        } catch {
            try? fm.removeItem(at: stagingDirectory)
            throw ClaudeUpdateError.badArchive(Self.describe(error))
        }
        do {
            let staged = try stagedBundle()
            try verifyBundle(staged, release: release, progress: progress)
            try refuseIfIntegrityOn(staged, version: release.version, progress: progress)
            let prepared = PreparedClaudeUpdate(release: release, installedVersion: installed, stagedApp: staged)
            try writeReady(prepared)
            progress("Новый Claude \(release.version) проверен. Можно ставить.")
            return prepared
        } catch {
            try? fm.removeItem(at: stagingDirectory)
            throw error
        }
    }

    /// Монтируем только для чтения в уникальную папку; даже ошибка копирования освобождает образ.
    /// Папку точки монтирования убирает `rmdir` — только пустую: не отцепился образ — его не трогаем.
    private func unpackDMG(_ archive: URL) throws {
        let fm = FileManager.default
        let mount = fm.temporaryDirectory.appendingPathComponent("pimp-claude-dmg-" + UUID().uuidString)
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        var attached = false
        defer {
            if attached { _ = try? Shell.run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
            rmdir(mount.path)
        }
        try Shell.run("/usr/bin/hdiutil", ["attach", archive.path, "-readonly", "-nobrowse", "-noautoopen",
                                          "-mountpoint", mount.path])
        attached = true
        let source = mount.appendingPathComponent("Claude.app")
        guard fm.fileExists(atPath: source.appendingPathComponent("Contents/Info.plist").path),
              (try source.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else {
            throw ClaudeUpdateError.badArchive("в DMG нет Claude.app")
        }
        try Shell.run("/usr/bin/ditto", [source.path, stagingDirectory.appendingPathComponent("Claude.app").path])
        do { try Shell.run("/usr/bin/hdiutil", ["detach", mount.path]) }
        catch { try Shell.run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
        attached = false
    }

    /// Второй замок Electron 41+ в новом бандле (A2): `used ≠ 0` — отказ, запомненный по версии;
    /// не прочитали — строка в журнал и дальше, как раньше.
    func refuseIfIntegrityOn(_ app: URL, version: String, progress: (String) -> Void) throws {
        switch Patcher.asarIntegrityVerdict(framework: Patcher.electronFramework(of: app)) {
        case .ok: return
        case .unknown(let why):
            progress("Второй замок Electron (__asar_integrity) не проверен: \(why).")
        case .refuse(let why):
            var refused = refusedVersions()
            refused[version] = why
            let body: [String: Any] = ["pimpBuild": pimpBuild, "versions": refused]
            if let data = try? JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys]) {
                try? FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
                try? data.write(to: downloadDirectory.appendingPathComponent(Self.refusedFileName), options: .atomic)
            }
            throw ClaudeUpdateError.integrityRefused(version: version, why: why)
        }
    }

    /// Запомненные отказы этой сборки Пимпа: версия → причина. Файла нет, он битый, прежнего
    /// вида (без сборки) или от другой сборки — отказов нет.
    func refusedVersions() -> [String: String] {
        let data = try? Data(contentsOf: downloadDirectory.appendingPathComponent(Self.refusedFileName))
        guard let root = data.flatMap({ (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }),
              root["pimpBuild"] as? String == pimpBuild,
              let versions = root["versions"] as? [String: String] else { return [:] }
        return versions
    }

    /// Причина, по которой Пимп не поставит найденное: все версии релиза новее стоящей уже
    /// отказаны этой сборкой (панель пишет «Claude X Пимп пока не патчит» без «Скачать»).
    /// `nil` — есть что качать.
    public func refusedReason(for release: ClaudeRelease) -> String? {
        guard let installed = try? installedVersion() else { return nil }
        let refused = refusedVersions()
        let newer = Self.versionGroups(release).map { $0[0].version }
            .filter { Self.compareVersions($0, installed) == .orderedDescending }
        guard let top = newer.first, newer.allSatisfy({ refused[$0] != nil }) else { return nil }
        return refused[top]
    }

    func checkArchive(_ archive: URL, _ release: ClaudeRelease) throws {
        let size = (try? FileManager.default.attributesOfItem(atPath: archive.path)[.size] as? NSNumber)?.int64Value ?? -1
        guard size == release.size else { throw ClaudeUpdateError.sizeMismatch(expected: release.size, got: size) }
        guard try Self.sha256(of: archive) == release.sha256 else { throw ClaudeUpdateError.checksumMismatch }
    }

    // -------------------------------------------------------------- готовность (ready.json)

    /// `ready.json` в папке распаковки: версия, формат, какая версия стояла, для какой копии, имя бандла.
    func writeReady(_ prepared: PreparedClaudeUpdate) throws {
        let record: [String: Any] = [
            "version": prepared.release.version,
            "format": prepared.release.format.rawValue,
            "installed": prepared.installedVersion,
            "appPath": appURL.standardizedFileURL.path,
            "bundle": prepared.stagedApp.lastPathComponent,
            "at": ISO8601DateFormatter().string(from: Date()),
        ]
        let data = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: stagingDirectory.appendingPathComponent(Self.readyFileName), options: .atomic)
    }

    /// Готовое обновление после перезапуска Пимпа (критик WF87 п. 8): та же копия Claude, стоит та же
    /// версия, что при подготовке, и она ниже готовой, бандл на месте и цел (`verifySignature` —
    /// ещё и подпись с Gatekeeper). Не сошлось — папка распаковки удаляется: голая папка не «готово».
    /// Звать, только пока `prepare` этой копии не идёт — иначе снесёт распаковку на ходу.
    public func loadReady(verifySignature: Bool = true) -> PreparedClaudeUpdate? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: stagingDirectory.path) else { return nil }
        let data = try? Data(contentsOf: stagingDirectory.appendingPathComponent(Self.readyFileName))
        guard let json = data.flatMap({ (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }),
              let version = json["version"] as? String,
              let then = json["installed"] as? String,
              json["appPath"] as? String == appURL.standardizedFileURL.path,
              let bundle = json["bundle"] as? String, !bundle.contains("/"), (bundle as NSString).pathExtension == "app",
              let format = (json["format"] as? String).flatMap(ClaudeRelease.Format.init(rawValue:)),
              let installed = try? installedVersion(), installed == then,
              Self.compareVersions(version, installed) == .orderedDescending else {
            try? fm.removeItem(at: stagingDirectory)
            return nil
        }
        let staged = stagingDirectory.appendingPathComponent(bundle, isDirectory: true)
        let release = ClaudeRelease(version: version, url: staged, sha256: "", size: 0, format: format)
        guard (try? verifyBundle(staged, release: release, signature: verifySignature, progress: { _ in })) != nil else {
            try? fm.removeItem(at: stagingDirectory)
            return nil
        }
        return PreparedClaudeUpdate(release: release, installedVersion: installed, stagedApp: staged)
    }

    // -------------------------------------------------------------- какую копию и можно ли в фоне

    /// Какую копию обновлять (критик WF87 п. 1): пропатченную (`installed.json appPath`), иначе выбранную
    /// человеком (`claudeAppPath`), иначе ту, что в /Applications. Остальные копии фон не трогает.
    public static func targetClaude(installedAppPath: String?, savedPath: String?, copies: [URL]) -> URL? {
        func key(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }
        func find(_ path: String?) -> URL? {
            guard let path = path, !path.isEmpty else { return nil }
            let wanted = key(URL(fileURLWithPath: path, isDirectory: true))
            return copies.first { key($0) == wanted }
        }
        return find(installedAppPath) ?? find(savedPath)
            ?? copies.first { $0.standardizedFileURL.deletingLastPathComponent().path == "/Applications" }
    }

    /// `appPath` из `installed.json` — копия, которую Пимп пропатчил последней.
    public static func installedAppPath(supportDirectory: URL = Patcher.defaultSupportDirectory) -> String? {
        guard let data = try? Data(contentsOf: supportDirectory.appendingPathComponent("installed.json")),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return json["appPath"] as? String
    }

    /// Запущенные процессы именно этой копии — по bundleURL, не по bundle id (критик WF87 п. 1).
    public func runningPIDs() -> [pid_t] { patcher().runningClaude().map { $0.processIdentifier } }

    /// Сколько `restartClaude` ждёт, что Claude снова запустился.
    public static let restartLaunchSeconds: TimeInterval = 20

    /// Перезапуск без обновления (`restart-claude`, WF108, #8176): те же `quitClaude` и
    /// `relaunchClaude`, что у `install`. Снимок окон и заморозку делает вызывающий — как перед
    /// обновлением. Claude не встал за `restartLaunchSeconds` — ошибка: окна возвращать некуда.
    public func restartClaude() throws {
        let current = patcher()
        do {
            try current.quitClaude(progress: { _ in })
        } catch PatchError.claudeWontQuit {
            throw ClaudeUpdateError.restartFailed("Claude не закрылся за 30 секунд. Закрой его сам (⌘Q) и повтори.")
        }
        var said = ""
        current.relaunchClaude(progress: { said = $0 })
        guard managesClaudeProcess else { return }
        let deadline = Date().addingTimeInterval(Self.restartLaunchSeconds)
        while current.runningClaude().isEmpty {
            guard Date() < deadline else {
                throw ClaudeUpdateError.restartFailed(said.isEmpty
                    ? "Claude закрылся, но не открылся за 20 секунд. Открой его сам из «Программ»." : said)
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
    }

    /// Место: архив на каждый источник гонки + 2 ГБ (распаковка ~0,9 ГБ и прежний бандл ~0,9 ГБ).
    public static func neededSpace(archiveSize: Int64, sources: Int) -> Int64 {
        max(archiveSize, 0) * Int64(max(sources, 1)) + 2_000_000_000
    }

    /// Можно ли качать в фоне: запись в папку Claude и место на дисках загрузки и распаковки.
    public func preflight(_ release: ClaudeRelease) -> ClaudeUpdatePreflight {
        let fm = FileManager.default
        guard fm.isWritableFile(atPath: parentDirectory.path) else { return .notWritable(parentDirectory.path) }
        let group = Self.versionGroups(release).first ?? [release]
        let largest = group.map { $0.size }.max() ?? 0
        let size: Int64 = largest > 0 ? largest : 400_000_000
        let needed = Self.neededSpace(archiveSize: size, sources: Self.sources(group).count)
        var probe = supportDirectory
        while !fm.fileExists(atPath: probe.path), probe.pathComponents.count > 1 { probe.deleteLastPathComponent() }
        let free = [parentDirectory, probe].compactMap { url -> Int64? in
            (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
                .volumeAvailableCapacityForImportantUsage ?? nil
        }.min()
        guard let available = free else { return .ok }
        return available >= needed ? .ok : .noSpace(needed: needed, free: available)
    }

    /// В архиве ровно один `.app` верхнего уровня.
    func stagedBundle() throws -> URL {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: stagingDirectory.path)) ?? []
        let apps = names.filter { !$0.hasPrefix(".") && $0 != "__MACOSX" && ($0 as NSString).pathExtension == "app" }
        guard apps.count == 1 else {
            throw ClaudeUpdateError.badArchive(apps.isEmpty ? "в архиве нет .app" : "в архиве \(apps.count) программ")
        }
        return stagingDirectory.appendingPathComponent(apps[0], isDirectory: true)
    }

    /// bundle id и версия из Info.plist; подпись Anthropic (`codesign --verify --deep --strict`
    /// с требованием на Team ID) и Gatekeeper (`spctl`).
    func verifyBundle(_ app: URL, release: ClaudeRelease, signature: Bool = true,
                      progress: (String) -> Void) throws {
        let info = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: info),
              let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else {
            throw ClaudeUpdateError.wrongBundle("не читается Info.plist")
        }
        let bundleID = plist["CFBundleIdentifier"] as? String ?? "—"
        guard bundleID == Patcher.claudeBundleID else {
            throw ClaudeUpdateError.wrongBundle("bundle id \(bundleID), а не \(Patcher.claudeBundleID)")
        }
        let version = plist["CFBundleShortVersionString"] as? String ?? "—"
        guard version == release.version else {
            throw ClaudeUpdateError.wrongBundle("внутри версия \(version), а фид обещал \(release.version)")
        }
        guard checksSignature, signature else { return }
        progress("Проверяю подпись Anthropic…")
        do {
            try Shell.run("/usr/bin/codesign", ["--verify", "--deep", "--strict",
                                                "-R=" + Self.signatureRequirement(), app.path])
        } catch {
            throw ClaudeUpdateError.signature("codesign: \(Self.describe(error))")
        }
        do {
            try Shell.run("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path])
        } catch {
            throw ClaudeUpdateError.signature("Gatekeeper: \(Self.describe(error))")
        }
    }

    // -------------------------------------------------------------- 3. подмена и патч (Claude закрывается)

    /// Закрыть Claude → прежний бандл в `Claude-<версия>.previous` → новый на место → патч.
    /// Сорвалась подмена или патч — прежний бандл возвращается и (при `relaunch`) открывается.
    /// Удача — прочие наши `.previous` и распаковка убираются: прежняя копия всегда одна.
    /// `relaunch: false` — Claude не открывается ни при удаче, ни при откате: откроет вызывающий.
    @discardableResult
    public func install(_ prepared: PreparedClaudeUpdate, relaunch: Bool = true,
                        progress: (String) -> Void = { _ in }) throws -> ClaudeUpdateOutcome {
        let fm = FileManager.default
        let current = patcher()
        try current.refuseIfInsideClaude()
        let installed = try current.appVersion()
        guard installed == prepared.installedVersion else {
            throw ClaudeUpdateError.changedMeanwhile("стоял \(prepared.installedVersion), сейчас \(installed)")
        }
        let staged = prepared.stagedApp
        guard fm.fileExists(atPath: staged.path) else {
            throw ClaudeUpdateError.changedMeanwhile("распакованного Claude \(prepared.release.version) больше нет")
        }
        // Ещё раз и целиком, пока Claude открыт: между prepare и install бандл лежал на диске.
        try verifyBundle(staged, release: prepared.release, progress: progress)
        // Право на запись — ДО закрытия Claude (промпт «Управление приложениями» всплывает первым).
        try current.waitForWritable(progress: progress)
        try current.quitClaude(progress: progress)

        let previous = parentDirectory.appendingPathComponent(Self.previousName(appName: appURL.lastPathComponent, version: installed), isDirectory: true)
        progress("Меняю Claude \(installed) на \(prepared.release.version)…")
        do {
            if fm.fileExists(atPath: previous.path) { try fm.removeItem(at: previous) } // наша же копия той же версии
            try fm.moveItem(at: appURL, to: previous)
        } catch {
            if relaunch { current.relaunchClaude(progress: progress) }
            throw ClaudeUpdateError.swapFailed(why: Self.describe(error), restored: fm.fileExists(atPath: appURL.path), previous: previous.path)
        }
        do {
            try fm.moveItem(at: staged, to: appURL)
        } catch {
            let restored = (try? fm.moveItem(at: previous, to: appURL)) != nil
            if restored && relaunch { current.relaunchClaude(progress: progress) }
            throw ClaudeUpdateError.swapFailed(why: Self.describe(error), restored: restored, previous: previous.path)
        }

        progress("Ставлю патч на новый Claude…")
        let patch: InstallOutcome
        do {
            patch = try patcher().install(relaunch: relaunch, progress: progress)
        } catch {
            let why = Self.describe(error)
            progress("Патч не лёг (\(why)) — возвращаю прежний Claude \(installed)…")
            // Новый бандл уходит обратно в распаковку (её уберёт следующая попытка), прежний — на место.
            try? fm.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            let aside = (try? fm.moveItem(at: appURL, to: stagingDirectory.appendingPathComponent("failed-\(UUID().uuidString).app"))) != nil
            let restored = aside && (try? fm.moveItem(at: previous, to: appURL)) != nil
            if restored {
                try? fm.removeItem(at: stagingDirectory)
                if relaunch { current.relaunchClaude(progress: progress) }
            }
            throw ClaudeUpdateError.patchFailed(why: why, restored: restored, previous: previous.path)
        }

        // Удача: прежняя копия одна, распаковка и архив больше не нужны.
        for name in (try? fm.contentsOfDirectory(atPath: parentDirectory.path)) ?? []
        where Self.isOwnPrevious(name, appName: appURL.lastPathComponent) && name != previous.lastPathComponent {
            try? fm.removeItem(at: parentDirectory.appendingPathComponent(name))
        }
        try? fm.removeItem(at: stagingDirectory)
        try? fm.removeItem(at: archiveURL(prepared.release))
        patcher().pruneBackups() // прочие прежние копии убраны — их бэкапы тоже (z7-r02)
        progress("Claude \(prepared.release.version) стоит. Прежний \(installed) лежит в \(previous.path).")
        return ClaudeUpdateOutcome(from: installed, to: prepared.release.version, patch: patch, previous: previous)
    }

    // -------------------------------------------------------------- сеть и файлы

    static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    /// Причина без вводной «Не узнал, есть ли…» — для склейки нескольких источников.
    static func reason(_ error: Error) -> String {
        if case ClaudeUpdateError.feed(let why) = error { return why }
        return describe(error)
    }

    static func makeSession(timeout: TimeInterval, resource: TimeInterval) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = resource
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }

    static func fetch(_ url: URL, timeout: TimeInterval) throws -> Data {
        let session = makeSession(timeout: timeout, resource: timeout)
        defer { session.finishTasksAndInvalidate() }
        let done = DispatchSemaphore(value: 0)
        var result: Result<Data, Error> = .failure(ClaudeUpdateError.feed("нет ответа"))
        session.dataTask(with: url) { data, response, error in
            defer { done.signal() }
            if let error = error { result = .failure(ClaudeUpdateError.feed(error.localizedDescription)); return }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                result = .failure(ClaudeUpdateError.feed("фид ответил \(http.statusCode)")); return
            }
            result = .success(data ?? Data())
        }.resume()
        done.wait()
        return try result.get()
    }

    /// Куда ведёт редирект — сам редирект не выполняется, файл не качается. Без идентификаторов.
    static func redirectTarget(_ url: URL, timeout: TimeInterval) throws -> URL {
        let catcher = RedirectCatcher()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config, delegate: catcher, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let done = DispatchSemaphore(value: 0)
        var result: Result<URL, Error> = .failure(ClaudeUpdateError.feed("нет ответа"))
        session.dataTask(with: url) { _, response, error in
            defer { done.signal() }
            if let target = catcher.target { result = .success(target); return }
            if let error = error { result = .failure(ClaudeUpdateError.feed(error.localizedDescription)); return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            result = .failure(ClaudeUpdateError.feed("редирект ответил \(code) без адреса"))
        }.resume()
        done.wait()
        return try result.get()
    }

    private final class RedirectCatcher: NSObject, URLSessionTaskDelegate {
        var target: URL?
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            target = request.url
            completionHandler(nil)
        }
    }

    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 8 * 1024 * 1024)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
