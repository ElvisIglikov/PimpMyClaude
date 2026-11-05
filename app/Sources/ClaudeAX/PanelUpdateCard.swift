import Foundation

// MARK: карточка «Обновление Claude» в три строки (#10307, #10305)

// Слово Элвиса 19.10.2026: «Скачалось обновление, тоже ужасный виджет… обновить сейчас вообще кнопка потерялась».
// Готовое обновление (`.ready`, `.busy`, `.timely`) — одна раскладка: подпись «Обновление Claude» и номер версии,
// одна причина цветом, главная кнопка во всю ширину и рядом, если нужна, маленькая вторая. Что в какой строке и какая
// кнопка что делает — здесь, без вида (тесты `PanelLikeWindows10308Tests`); рисует `UpdateBlockView`.

extension PimpPanelText {
    public struct UpdateCard: Equatable {
        /// Цвет строки причины: зелёный — самое время, жёлтый — работа идёт или вопрос, серый — просто готово.
        public enum Tone: Equatable { case good, warn, quiet }

        /// Кнопка карточки — те же действия панели, что были до #10307; с WF283 вторая кнопка готового —
        /// «При следующем запуске» (слово Элвиса 23.10.2026: «две кнопки обновить сейчас… или обновить при следующем
        /// запуске»), она же заменила «Позже».
        public enum Action: Equatable {
            case update, updateNow, updateAnyway, wait, nextLaunch

            public var title: String {
                switch self {
                case .update, .updateNow: return "Обновить сейчас"
                case .updateAnyway: return "Обновить всё равно"
                case .wait: return "Подождать"
                case .nextLaunch: return "При запуске"
                }
            }
        }

        public let version: String
        public let reason: String
        public let tone: Tone
        public let main: Action
        public let second: Action?
        /// Подсказка главной кнопки.
        public let help: String

        public init(version: String, reason: String, tone: Tone, main: Action, second: Action? = nil,
                    help: String = PimpPanelText.updateCardHelp) {
            self.version = version
            self.reason = reason
            self.tone = tone
            self.main = main
            self.second = second
            self.help = help
        }
    }

    /// Подсказка главной кнопки: абзац «Claude закроется…» ушёл из карточки сюда (#10307).
    public static let updateCardHelp = "Claude закроется секунд на 20 — окна вернутся на места"
    /// В `.busy` — ещё и что обновление подождёт само (была строка под пилюлями, #10305).
    public static let updateCardBusyHelp = "Подожду, пока закончат, и предложу обновиться. " + updateCardHelp

    /// Карточку скрыли крестиком (#10765, слово Элвиса 23.10.2026: «обновление… очень раздражает, то, что я не могу
    /// его скрыть»): здесь лежит скрытая версия; вышла другая — карточка вернётся сама.
    public static let updateHiddenKey = "claudeUpdateHiddenVersion"

    /// Скрыта ли карточка: только готовое обновление (`updateCard`) той самой версии. Загрузка, установка, сбой и
    /// вопрос «обновить всё равно?» — всегда видны: это ответ на нажатие (кнопка уведомления тоже), не напоминание.
    public static func updateCardHidden(_ block: UpdateBlock, hidden: String?) -> Bool {
        if case .ready(_, _?) = block { return false }
        guard let hidden = hidden, let card = updateCard(block, size: nil) else { return false }
        return card.version == hidden
    }

    /// Карточка готового обновления; прочие состояния блока (качается, ставится, сбой, отложено…) — nil, у них свой
    /// вид. `size` — «374 МБ» скачанного. Вторая кнопка готового — «При запуске» (WF283): и в «идёт работа» — она
    /// сворачивает карточку в строку, а обновление встанет, когда Claude закроют.
    public static func updateCard(_ block: UpdateBlock, size: String?) -> UpdateCard? {
        switch block {
        case .ready(let version, nil):
            return UpdateCard(version: version, reason: "подпись Anthropic ✓" + (size.map { " · " + $0 } ?? ""),
                              tone: .quiet, main: .update, second: .nextLaunch)
        case .ready(let version, let question?):
            return UpdateCard(version: version, reason: question, tone: .warn, main: .updateAnyway, second: .wait)
        case .busy(let version, let work):
            let what = work.prefix(1).lowercased() + work.dropFirst()
            return UpdateCard(version: version, reason: "идёт работа: " + what, tone: .warn, main: .updateNow,
                              second: .nextLaunch, help: updateCardBusyHelp)
        case .timely(let version, let reason):
            return UpdateCard(version: version, reason: "самое время: " + reason, tone: .good, main: .updateNow,
                              second: .nextLaunch)
        case .none, .available, .downloading, .verifying, .planned, .snoozed, .installing, .done, .failed:
            return nil
        }
    }
}
