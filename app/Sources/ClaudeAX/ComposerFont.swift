import Foundation

/// Размер шрифта в поле ввода (WF107 #8126, контракт К2): один размер на все окна Claude. Владелец значения —
/// `localStorage` страницы (его крутит и колесо Диктатора ⌃⌥⌘[ ]); у приложения — зеркало для галки в меню
/// «🔡 Размер шрифта в поле ▸» и для возврата после переустановки Claude. Здесь — чистые функции: зеркало,
/// шаги меню, байты команды, разбор ручки порта `/composer-font`.
enum ComposerFont {
    /// Команда страницам: `{id, action:"composer-font", at, px:N|null}`; примерка —
    /// `{id, action, at, title, match|chat, preview:true, px}`.
    static let action = "composer-font"
    /// Зеркало в UserDefaults приложения: Int 11…32, нет ключа — «Как у Claude».
    static let defaultsKey = "composerFontSize"
    static let range = 11...32
    /// Строки подменю под «Как у Claude».
    static let steps = [12, 13, 14, 15, 16, 18, 20, 22, 24]
    /// Возврат после переустановки — не чаще раза в столько секунд.
    static let restoreInterval: TimeInterval = 10

    /// Значение в границах; nil остаётся nil.
    static func clamp(_ px: Int?) -> Int? {
        px.map { min(max($0, range.lowerBound), range.upperBound) }
    }

    /// Зеркало (с зажимом — ключ мог поправить человек); нет ключа или не число — nil.
    static func mirror(in defaults: UserDefaults = .standard) -> Int? {
        clamp(defaults.object(forKey: defaultsKey) as? Int)
    }

    static func setMirror(_ px: Int?, in defaults: UserDefaults = .standard) {
        if let px = clamp(px) { defaults.set(px, forKey: defaultsKey) } else { defaults.removeObject(forKey: defaultsKey) }
    }

    /// Когда размер выбран в меню (хвост WF107): пока команда идёт по очереди канала, страница ещё может
    /// прислать прежнее значение (пинг загрузки) — и «Как у Claude» воскресало бы из зеркала.
    static let chosenAtKey = "composerFontChosenAt"
    /// Столько секунд после выбора в меню пинг с другим числом зеркало не трогает.
    static let settleInterval: TimeInterval = 5

    /// Выбор в меню: зеркало и время выбора.
    static func choose(_ px: Int?, in defaults: UserDefaults = .standard, at: Date = Date()) {
        setMirror(px, in: defaults)
        defaults.set(at.timeIntervalSince1970, forKey: chosenAtKey)
    }

    /// Пинг с этим числом — эхо старого значения, пришедшее после выбора в меню: зеркало не трогать.
    static func isStale(_ px: Int, in defaults: UserDefaults, at: Date) -> Bool {
        guard let chosen = defaults.object(forKey: chosenAtKey) as? Double else { return false }
        let since = at.timeIntervalSince1970 - chosen
        return since >= 0 && since < settleInterval && px != mirror(in: defaults)
    }

    /// Шаги подменю: текущее значение, которого нет в списке (колесо дало 17), — на своём месте по порядку.
    static func menuSteps(current: Int?) -> [Int] {
        guard let current = current, !steps.contains(current) else { return steps }
        return (steps + [current]).sorted()
    }

    /// Поля команды выбора (после id, action, at): `px` числом или `null`.
    static func fields(px: Int?) -> [(key: String, value: CommandValue)] {
        [(key: "px", value: clamp(px).map { .number($0) } ?? .null)]
    }

    /// Поля примерки: адрес — как у примерки темы (`themeAddress`: заголовок и `match` либо `chat`).
    static func previewFields(title: String, match: String?, chat: String?,
                              px: Int?) -> [(key: String, value: CommandValue)] {
        var fields: [(key: String, value: CommandValue)] = [(key: "title", value: .string(title))]
        if let match = match { fields.append((key: "match", value: .string(match))) }
        if let chat = chat { fields.append((key: "chat", value: .string(chat))) }
        fields.append((key: "preview", value: .bool(true)))
        return fields + self.fields(px: px)
    }

    /// Страница → приложение: `GET /composer-font?px=<N|none>&chat=<local_…>`. `px` nil — `none`.
    struct Ping: Equatable {
        let px: Int?
        let chat: String
    }

    /// Разбор строки запроса; `px` вне 11…32 или мусор, нет чата или мусорный — nil. Чистая.
    static func parse(_ head: String) -> Ping? {
        let line = head.prefix { $0 != "\r" && $0 != "\n" }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
              let components = URLComponents(string: "http://127.0.0.1" + parts[1]),
              components.path == "/composer-font" else { return nil }
        let value = { (name: String) in components.queryItems?.first(where: { $0.name == name })?.value }
        guard let chat = HtmlChromeOpener.chatID(value("chat")), let raw = value("px") else { return nil }
        if raw == "none" { return Ping(px: nil, chat: chat) }
        guard raw.count <= 2, raw.allSatisfy({ $0.isASCII && $0.isNumber }), let px = Int(raw), range.contains(px)
        else { return nil }
        return Ping(px: px, chat: chat)
    }
}

/// Приём пинга страницы (контракт К2): значение — в зеркало, страницам ничего (нет петли); `none` при непустом
/// зеркале — страница потеряла `localStorage` (переустановка Claude), ей возвращается значение зеркала, не чаще
/// раза в `restoreInterval`. Звать на главной.
final class ComposerFontMirror {
    private let defaults: UserDefaults
    private let now: () -> Date
    private var lastRestoreAt: Date?

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    var px: Int? { ComposerFont.mirror(in: defaults) }

    /// Возвращает размер, который надо разослать страницам командой; nil — ничего не слать.
    func receive(_ ping: ComposerFont.Ping) -> Int? {
        let at = now()
        if let px = ping.px {
            if !ComposerFont.isStale(px, in: defaults, at: at) { ComposerFont.setMirror(px, in: defaults) }
            return nil
        }
        guard let px = self.px else { return nil }
        if let last = lastRestoreAt, at >= last, at.timeIntervalSince(last) < ComposerFont.restoreInterval { return nil }
        lastRestoreAt = at
        return px
    }
}
