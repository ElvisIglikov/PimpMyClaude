import Foundation

/// Черновик прежнего чата при замене чата главного окна (#11201, WF302; слово Элвиса 30.10 ~17:45: «Я там скриншоты
/// ещё закреплял, скриншоты не закрепились… диктовки ещё куски большие не вставились»). Страница (раздел 12ч)
/// переносит набранное и вложения в поле нового чата и говорит исход в `status().newWindow.carry`; это его слепок.
/// Контракт — `docs/contracts/640-wf302-renew-draft.md`.
struct DraftCarry: Equatable {
    /// `wait` — переносится; `ok` — всё в поле нового чата; `part` — текст лёг, вложения не все; `fail` — не лёг,
    /// черновик в прежнем чате; `kept` — новый чат не родился, черновик остался в прежнем; `back` — вернули в прежний.
    static let states: Set<String> = ["wait", "ok", "part", "fail", "kept", "back"]
    static let whyLimit = 120

    let state: String
    let chars: Int
    let want: Int
    let landed: Int
    let why: String

    /// Не объект или состояние не из списка — nil (старая страница поля не шлёт вовсе).
    static func parse(_ value: Any?) -> DraftCarry? {
        guard let map = value as? [String: Any], let state = map["state"] as? String, states.contains(state) else {
            return nil
        }
        let count: (String) -> Int = { key in
            guard let number = map[key] as? NSNumber, number.doubleValue.isFinite else { return 0 }
            return max(0, min(number.intValue, 1_000_000))
        }
        let raw = ((map["why"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let why = raw.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) } ? "" : String(raw.prefix(whyLimit))
        return DraftCarry(state: state, chars: count("chars"), want: count("want"),
                          landed: count("landed"), why: why)
    }

    /// Поле `draft` ответа `renew-window`: `{state, chars, want, landed, why?}`.
    var field: CommandValue {
        var all: [(key: String, value: CommandValue)] = [
            (key: "state", value: .string(state)),
            (key: "chars", value: .number(chars)),
            (key: "want", value: .number(want)),
            (key: "landed", value: .number(landed)),
        ]
        if !why.isEmpty { all.append((key: "why", value: .string(why))) }
        return .object(all)
    }
}

/// Пауза в наборе перед заменой чата (#11201): Элвис печатает или диктует (Диктатор жмёт синтетические клавиши) —
/// замену откладываем, пока клавиатура не помолчит `idleSeconds`, но не дольше `waitSeconds`: дальше меняем как есть,
/// черновик переедет сам.
enum RenewTyping {
    static let idleSeconds: TimeInterval = 3
    static let waitSeconds: TimeInterval = 60
    /// Прошлое ожидание старше этого — уже другое (запрос бросили), считаем заново.
    static let forgetSeconds: TimeInterval = 90

    /// Ждать ли ещё: начало ожидания (сохранить и ответить `busy`) или nil — менять сейчас.
    /// `idle` — секунды с последней клавиши; nil — не знаем, не ждём.
    static func hold(idle: TimeInterval?, since: Date?, at: Date) -> Date? {
        guard let idle = idle, idle < idleSeconds else { return nil }
        let start = since.flatMap { at.timeIntervalSince($0) < forgetSeconds ? $0 : nil } ?? at
        return at.timeIntervalSince(start) < waitSeconds ? start : nil
    }
}
