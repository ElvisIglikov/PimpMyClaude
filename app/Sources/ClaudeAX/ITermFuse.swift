import AppKit
import CoreGraphics
import Foundation
import Patcher

// Предохранитель окон iTerm (#10976, 27.10.2026: в iTerm 106, потом 380 окон и 3 550 псевдотерминалов — tmux не мог
// завести сессию). Причина была в «Initial Text» профиля «Default» — `…/iterm/open-tabs.command; exit`, след пробы
// 22.10: профиль «Пимп» его наследовал, и каждое новое окно iTerm запускало ещё окно с вкладками. Теперь Пимп держит в
// своём профиле явно пустой «Initial Text» (`ensureProfile`) и не открывает iTerm, пока какой-то профиль сам запускает
// окна, окон больше `maxWindows` или псевдотерминалы у предела macOS (`alarm`); причина — строкой в блоке «Терминалы».
extension ITermHub {
    /// Окон iTerm больше — что-то плодит окна, новых не открываем.
    static let maxWindows = 30
    /// Доля предела псевдотерминалов macOS (`kern.tty.ptmx_max`), с которой новых окон не открываем.
    static let ptyShare = 0.8
    /// Профиль «Пимп» (iTerm перечитывает файл сам, без перезапуска).
    static let profileGuid = "pimp-terminal-chats"
    static var profileFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/iTerm2/DynamicProfiles/pimp.json")
    }

    /// «Initial Text» запускает окна или скрипты: `.command`, AppleScript, `open`.
    static func launches(_ text: String) -> Bool {
        let lower = text.lowercased()
        if [".command", "osascript", "applescript", ".scpt"].contains(where: lower.contains) { return true }
        return lower.range(of: #"(^|[\s;&|(])open(\s|$)"#, options: .regularExpression) != nil
    }

    /// Имя первого профиля, чей «Initial Text» запускает окна; такого нет — nil.
    static func launchingProfile(_ profiles: [[String: Any]]) -> String? {
        profiles.first { launches($0["Initial Text"] as? String ?? "") }.map { $0["Name"] as? String ?? "?" }
    }

    /// Почему iTerm сейчас не открывать; можно — nil.
    static func alarm(profile: String?, windows: Int, ptys: (used: Int, limit: Int)) -> String? {
        if let profile = profile { return "iTerm: профиль «\(profile)» сам открывает окна (Initial Text) — окна не открываю" }
        if windows > maxWindows { return "iTerm: \(windows) окон — что-то плодит окна, новые не открываю" }
        if ptys.limit > 0, Double(ptys.used) >= Double(ptys.limit) * ptyShare {
            return "Терминалов \(ptys.used) из \(ptys.limit) — новые окна iTerm не открываю"
        }
        return nil
    }

    /// Текст профиля, где у профиля Пимпа «Initial Text» пустой; уже пустой или файл не разобрать — nil.
    static func profileFixed(_ data: Data) -> Data? {
        guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var list = root["Profiles"] as? [[String: Any]] else { return nil }
        var changed = false
        for index in list.indices
        where list[index]["Guid"] as? String == profileGuid && list[index]["Initial Text"] as? String != "" {
            list[index]["Initial Text"] = ""
            changed = true
        }
        guard changed else { return nil }
        root["Profiles"] = list
        return try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    // MARK: исполнение

    /// Свой профиль: «Initial Text» — явно пустой, иначе профиль наследует его у «Default». Файла нет — ничего. Временный
    /// файл — не в DynamicProfiles: iTerm читает там любой файл. Ответ — переписан ли.
    @discardableResult
    static func ensureProfile(file: URL = profileFile,
                              tmp: URL = SupportFiles.directory.appendingPathComponent("iterm/pimp.json.tmp")) -> Bool {
        guard let data = FileManager.default.contents(atPath: file.path), let fixed = profileFixed(data) else { return false }
        try? FileManager.default.createDirectory(at: tmp.deletingLastPathComponent(), withIntermediateDirectories: true)
        return SupportFiles.writeAtomic(file, fixed, tmp: tmp, permissions: 0o644)
    }

    /// Профили iTerm: из его настроек и из файлов DynamicProfiles.
    static func profiles() -> [[String: Any]] {
        var out = CFPreferencesCopyAppValue("New Bookmarks" as CFString, bundle as CFString) as? [[String: Any]] ?? []
        let dir = profileFile.deletingLastPathComponent()
        for name in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where name.hasSuffix(".json") {
            guard let data = FileManager.default.contents(atPath: dir.appendingPathComponent(name).path),
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let list = root["Profiles"] as? [[String: Any]] else { continue }
            out += list
        }
        return out
    }

    /// Окна iTerm на всех столах, свёрнутые тоже; служебные полоски (у iTerm их по одной на экран, 30 pt) не в счёт.
    static func windowCount() -> Int {
        let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: bundle).map(\.processIdentifier))
        guard !pids.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return 0 }
        return list.filter { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int, pids.contains(pid_t(pid)),
                  info[kCGWindowLayer as String] as? Int == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return false }
            return rect.width >= 100 && rect.height >= 100
        }.count
    }

    /// Псевдотерминалы: заняты (`/dev/ttysNNN`) и предел macOS; предел не прочли — 0.
    static func ptys() -> (used: Int, limit: Int) {
        let used = ((try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []).filter { name in
            name.hasPrefix("ttys") && name.count >= 7 && name.dropFirst(4).allSatisfy { $0.isASCII && $0.isNumber }
        }.count
        var limit: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.tty.ptmx_max", &limit, &size, nil, 0) == 0 else { return (used, 0) }
        return (used, Int(limit))
    }

    static func alarm() -> String? {
        alarm(profile: launchingProfile(profiles()), windows: windowCount(), ptys: ptys())
    }

    /// Строка блока «Терминалы»: режим iTerm, а предохранитель держит — почему; иначе nil.
    public static func panelAlarm(defaults: UserDefaults = .standard) -> String? {
        guard installed, defaults.bool(forKey: modeKey) else { return nil }
        return alarm()
    }
}
