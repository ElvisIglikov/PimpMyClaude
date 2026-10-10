import ApplicationServices
import CoreFoundation
import Foundation

/// Выключатель Авто-Allow (К3, WF121) и общий повтор команд страницам по поколениям.
/// Кнопки разрешения проверяет и нажимает страница; здесь только доставка состояния, без AX-кликера.
///
/// localStorage умирает вместе с перезапуском Claude, а страницы грузятся позже смены pid
/// (критик WF84, «Важное» 5): флаг повторяется в каждом поколении по образцу `themes-restore`
/// — первый тик, где у Claude есть окна, и дальше на смену состава окон, не чаще раза в 5 с
/// и не больше трёх раз. Иначе «выкл» после перезапуска молча стал бы «вкл».
///
/// Класс не потокобезопасен: живёт на главной очереди вместе с общим тиком 2 с.
final class AutoAllowSwitch {
    static let resendLimit = 3
    static let resendInterval: TimeInterval = 5
    /// Флаг тумблера; без сохранённого выбора Авто-Allow выключен.
    var on = false

    private var sent = 0
    private var lastSentAt: Date?
    private var sentTitles: [String]?

    /// Поля К3 после id, action, at: on — именно строка, без адресации окна.
    static func fields(on: Bool) -> [(key: String, value: CommandValue)] {
        [(key: "on", value: .string(on ? "true" : "false"))]
    }

    /// Сколько команд принял канал в этом поколении (`autoAllow=`, `mic=`), не ACK страницы.
    var status: String { "\(on ? "on" : "off")/\(sent)" }

    /// Новое поколение: старт приложения или смена pid Claude.
    func beginGeneration() {
        sent = 0
        lastSentAt = nil
        sentTitles = nil
    }

    /// Тик: слать ли флаг сейчас. `titles` — окна Claude на экране; нет окон — страниц нет,
    /// слать некому. Ушла команда — true.
    @discardableResult
    func tick(titles: [String], at: Date, send: (Bool) -> Bool) -> Bool {
        guard sent < AutoAllowSwitch.resendLimit, !titles.isEmpty else { return false }
        let wanted = titles.sorted()
        if let last = lastSentAt {
            guard at.timeIntervalSince(last) >= AutoAllowSwitch.resendInterval,
                  wanted != sentTitles else { return false }
        }
        guard send(on) else { return false }
        sent += 1
        lastSentAt = at
        sentTitles = wanted
        return true
    }
}

/// One snapshot BEFORE any startup migration writes defaults. Existing explicit choices win.
public enum AutomationDefaults {
    public static let allowKey = "autoAllowEnabled"
    public static let continueKey = "autoContinueEnabled"
    public static let continueMigrationKey = "autoContinuePreservePageChoice"
    public static let mirrorsKey = "claudeThirdPartySources"
    public static let initializedKey = "automationDefaultsInitialized"
    public static let downloadQuestionKey = "claudeAutoDownloadQuestionPending"

    public static func isLegacy(values: [String: Any], patched: Bool) -> Bool {
        let oldKeys: Set<String> = [allowKey, "setupWindowSeen", "loginItemConfigured", "claudeAppPath",
                                   "minimizeMenuEnabled", "blockQuitEnabled", "projectPaintEnabled", "projectHints",
                                   "themeByWindow", "themeAll", "fontByWindow", "fontAll", "sizeByWindow", "sizeAll",
                                   "frameByWindow", "frameAll", "lookByWindow", "lookAll", "arrangeMode",
                                   "liveColors.on", "liveColors.mode", "liveColors.period",
                                   "dimOthers", "dimLevel", "sendLookStyle", "sendLookSize"]
        return patched || values.keys.contains { oldKeys.contains($0) }
    }

    public static func legacyMarker(_ data: Data?) -> Bool {
        guard let data = data, let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let version = record["version"] as? String, !version.isEmpty,
              let hash = record["headerSHA256"] as? String, !hash.isEmpty else { return false }
        // A newly created v8 marker alone does not prove a pre-migration installation.
        let loader = record["loaderVersion"] as? Int ?? 0
        return loader >= 0 && loader < 8
    }

    public static func migrate(_ defaults: UserDefaults = .standard, values: [String: Any], legacyPatched: Bool) {
        let legacy = isLegacy(values: values, patched: legacyPatched)
        // К3 возвращается после WF119 p2: новый ключ обрабатываем даже после общей миграции.
        // Уже мигрировавшая установка без тумблера остаётся выключенной; числа/строки не Bool.
        if let stored = values[allowKey] {
            let isBool = (stored as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
            if !isBool {
                // UserDefaults считает числовой 0 равным false и может пропустить замену типа.
                defaults.removeObject(forKey: allowKey)
                defaults.set(false, forKey: allowKey)
            }
        } else {
            defaults.set(values[initializedKey] == nil && legacy, forKey: allowKey)
        }
        guard values[initializedKey] == nil else { return }
        if values[ClaudeUpdateMenu.autoDownloadKey] == nil { defaults.set(legacy, forKey: ClaudeUpdateMenu.autoDownloadKey) }
        if values[mirrorsKey] == nil { defaults.set(legacy, forKey: mirrorsKey) }
        if values[continueKey] == nil {
            defaults.set(legacy, forKey: continueKey)
            defaults.set(legacy, forKey: continueMigrationKey)
        } else if values[continueMigrationKey] == nil { defaults.set(false, forKey: continueMigrationKey) }
        defaults.set(!legacy && values[ClaudeUpdateMenu.autoDownloadKey] == nil, forKey: downloadQuestionKey)
        defaults.set(true, forKey: initializedKey)
    }
}
