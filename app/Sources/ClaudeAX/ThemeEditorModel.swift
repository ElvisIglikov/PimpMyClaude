import Foundation

/// Чем кончилось «Сохранить» — панели надо различать отказ и неудачу (о неудаче она говорит
/// алертом, об отказе молчит).
enum ThemeEditorSave: Equatable {
    /// Имя не ввели (или ввели пустое, или отказались перезаписывать чужую тему).
    case cancelled
    /// Имя ввели, а `my-themes.json` не записался.
    case failed
    case saved(MyTheme)
}

/// Логика панели «Своя тема» без единого AppKit-класса (критик В7 плана WF20): ручки,
/// троттлинг примерки и запись своей темы. `swift test` идёт без сессии окна, и тест на живой
/// `NSPanel` либо повис бы, либо проверял не то, — поэтому всё проверяемое живёт здесь,
/// а `ThemeEditor.swift` остаётся проводкой AppKit.
final class ThemeEditorModel {
    /// Шаг троттлинга примерки — ровно шаг опроса лоадера (критик В3): чаще писать бессмысленно
    /// (`command.json` читается раз в 500 мс), а очередь канала с её зазором 0,6 с от частых
    /// записей встала бы колом. Честная задержка от ручки до цвета — 0,5…1,0 с.
    static let previewInterval: TimeInterval = 0.5

    private(set) var knobs: ThemeKnobs
    /// Тема, которую правим («✏️ Изменить мою тему»); nil — «🎚 Своя тема…», сохранение
    /// заведёт новую запись.
    let editing: MyTheme?

    /// Примерить ручки (`preview:true`, один слой темы) — ставит `ThemeEditor`.
    var onPreview: (ThemeKnobs) -> Void = { _ in }
    /// Конец примерки (`preview:false` без слоёв): окну возвращается сохранённое.
    var onEndPreview: () -> Void = {}

    /// Что ушло в примерку — по этому списку тест и считает троттлинг.
    private(set) var previews: [ThemeKnobs] = []
    /// Была ли хоть одна примерка. Пока ручку не тронули, окно не перекрашивается (критик В5),
    /// и гасить на выходе нечего.
    private(set) var previewing = false

    /// Ручки подобраны по палитре, а не взяты из файла — панель говорит об этом строкой.
    var knobsAreGuessed: Bool { editing?.knobs == nil }

    private let now: () -> Date
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private var sentAt: Date?
    private var pending: ThemeKnobs?
    private var waiting = false

    /// Часы и таймер подставляются в тестах — ровно как у `CommandChannel`.
    init(knobs: ThemeKnobs, editing: MyTheme? = nil,
         now: @escaping () -> Date = Date.init,
         schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, block in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
         }) {
        self.knobs = knobs
        self.editing = editing
        self.now = now
        self.schedule = schedule
    }

    // MARK: - ручки

    func set(hue: Int) { change { $0.hue = hue } }
    func set(accent: Int) { change { $0.accent = accent } }
    func set(strength: Int) { change { $0.strength = strength } }
    func set(light: Bool) { change { $0.light = light } }

    /// Ручку подвинули. Значение, которое ничего не меняет (ползунок вернули на место,
    /// нажали уже выбранную половину тумблера), примерки не стоит: открытие панели и возня
    /// с ручками вхолостую окно не перекрашивают.
    private func change(_ body: (inout ThemeKnobs) -> Void) {
        var next = knobs
        body(&next)
        guard next != knobs else { return }
        knobs = next
        pending = next
        flush()
    }

    private var secondsSinceSend: TimeInterval {
        sentAt.map { now().timeIntervalSince($0) } ?? .greatestFiniteMagnitude
    }

    /// Одна примерка на интервал; последнее значение досылается всегда — иначе окно осталось бы
    /// в цвете, на котором ползунок был полсекунды назад.
    private func flush() {
        guard !waiting, let next = pending else { return }
        let wait = ThemeEditorModel.previewInterval - secondsSinceSend
        guard wait <= 0 else {
            waiting = true
            schedule(wait) { [weak self] in
                self?.waiting = false
                self?.flush()
            }
            return
        }
        pending = nil
        sentAt = now()
        previews.append(next)
        previewing = true
        onPreview(next)
    }

    // MARK: - выходы

    /// «Отмена», крестик, окно исчезло: примерку гасим — иначе окно осталось бы в цвете
    /// ползунка и перестало бы перекрашиваться при смене чата (`syncChatTheme` выходит
    /// на `previewing`).
    func cancel() {
        pending = nil
        guard previewing else { return }
        previewing = false
        onEndPreview()
    }

    /// «Сохранить»: спросить имя, записать свою тему, вернуть записанное. Диалоги приходят
    /// замыканиями (`ask` — имя, `confirm` — «Перезаписать «X»?»), поэтому путь целиком
    /// проверяется тестом без AppKit.
    ///
    /// Примерку здесь не гасим: её погасит закрепляющая команда, которую панель пошлёт
    /// сохранённой темой (`endPreviewExcept`).
    func save(into store: MyThemesStore, font: Font?, size: Size?, frame: Bool,
              ask: (String) -> String?, confirm: (String) -> Bool) -> ThemeEditorSave {
        pending = nil
        guard let raw = ask(editing?.name ?? knobs.suggestedName) else { return .cancelled }
        let name = MyThemesStore.clean(name: raw)
        guard !name.isEmpty else { return .cancelled }
        // Имя занято ЧУЖОЙ записью — тот же вопрос, что у «Сохранить как мою тему…» (WF14):
        // отказались — не пишем вовсе, согласились — сливаемся в неё.
        if let taken = MyThemesStore.matching(name: name, in: store.load()),
           taken.id != editing?.id, !confirm(taken.name) { return .cancelled }
        let theme = knobs.theme(id: editing?.id ?? ThemeKnobs.previewID, name: name)
        let saved: MyTheme?
        if let editing = editing {
            saved = store.update(id: editing.id, name: name, theme: theme, font: font,
                                 size: size, frame: frame, knobs: knobs)
        } else {
            saved = store.add(name: name, theme: theme, font: font, size: size, frame: frame,
                              knobs: knobs).flatMap { MyThemesStore.matching(name: name, in: $0) }
        }
        // Файл не записался — примерка остаётся живой: панель закроется и вернёт окну цвет,
        // который на нём и был. Записалась — примерку погасит закрепляющая команда.
        guard let my = saved else { return .failed }
        previewing = false
        return .saved(my)
    }
}
