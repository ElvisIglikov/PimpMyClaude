import Foundation

/// Размер шрифта в поле ввода (WF107 #8126, контракт К2): один размер на все окна Claude. Владелец значения —
/// `localStorage` страницы (его крутит колесо Диктатора ⌃⌥⌘[ ]); у приложения — зеркало для возврата после
/// переустановки Claude (выбор в меню «🔡 Размер шрифта в поле ▸» снят вместе с меню, WF237). Здесь — чистые
/// функции: зеркало, байты команды, разбор ручки порта `/composer-font`.
enum ComposerFont {
    /// Команда страницам: `{id, action:"composer-font", at, px:N|null}`.
    static let action = "composer-font"
    /// Зеркало в UserDefaults приложения: Int 11…32, нет ключа — «Как у Claude».
    static let defaultsKey = "composerFontSize"
    static let range = 11...32
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

    /// Поля команды выбора (после id, action, at): `px` числом или `null`.
    static func fields(px: Int?) -> [(key: String, value: CommandValue)] {
        [(key: "px", value: clamp(px).map { .number($0) } ?? .null)]
    }

    /// Страница → приложение: `GET /composer-font?px=<N|none>&chat=<local_…>`. `px` nil — `none`.
    struct Ping: Equatable {
        let px: Int?
        let chat: String
    }

    /// Разбор строки запроса; `px` вне 11…32 или мусор, нет чата или мусорный — nil. Чистая.
    static func parse(_ head: String) -> Ping? {
        guard let components = HtmlChromeOpener.query(head, path: "/composer-font") else { return nil }
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
            ComposerFont.setMirror(px, in: defaults)
            return nil
        }
        guard let px = self.px else { return nil }
        if let last = lastRestoreAt, at >= last, at.timeIntervalSince(last) < ComposerFont.restoreInterval { return nil }
        lastRestoreAt = at
        return px
    }
}
