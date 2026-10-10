import Foundation

/// Пустое окно Claude Code проекта (план WF88, вариант V-N, контракт К17): штатный пункт
/// Claude File ▸ «New Session in New Window» открывает попап-черновик `code-draft` с пустым
/// полем ввода, и по первому Enter тот же попап сам становится чатом. Своего окна у Пимпа нет.
///
/// Здесь только чистая часть — подписи пункта, выбор пункта в дереве заголовков меню, узнавание
/// черновика по заголовку и поля команды `draft-setup`. AX и таймеры живут в `ClaudeActions`
/// и `PimpChannel`, тесты гоняют эту часть без Claude.
///
/// Живая проверка S.0 (25.09, Claude 2.9939.2, `/Applications`): пункт жмётся AXPress и когда
/// Claude позади; черновик родился за 0,17 с, 900×700 уступом у окон (не на рамке служебного
/// окна 800×600), сразу с заголовком «Code», главным, но без фокуса; в композере есть чип папки,
/// модель и эффорт; закрылся красной кнопкой бесследно. Отсюда путь папки «Ч»: папку ставит
/// страница чипом по полю `folder` команды `draft-setup` (правка критика V-N п. 6 — стор дома
/// не трогаем вовсе).
enum BlankWindow {
    /// Ключ подписи пункта в таблицах локалей Claude (`Resources/*.json`).
    static let messageKey = "U//bQDu9Yk"
    /// Подписи пункта в Claude 2.9939.2, побайтно (контракт К17): таблицы локалей бандла
    /// дописывают к ним новые, а эти остаются запасом, если бандл не прочитался.
    static let fallbackLabels = [
        "New Session in New Window", "Neue Sitzung in neuem Fenster",
        "Nueva sesión en una ventana nueva", "Nouvelle session dans une nouvelle fenêtre",
        "नई विंडो में नया सत्र", "Sesi Baru di Jendela Baru",
        "Nuova sessione in una nuova finestra", "新規ウィンドウで新規セッション", "새 창에서 새 세션",
        "Nova sessão em nova janela",
    ]
    /// Таблица локали больше этого — не наша, не читаем.
    static let maxTableBytes = 2 * 1024 * 1024
    /// Заголовки черновика (обрезка пробелов, нижний регистр): до Enter он зовётся «Code».
    static let draftTitles: Set<String> = ["code"]
    /// Сколько ждём черновик от НАЖАТИЯ (правка критика V-N п. 2) и шаг опроса.
    static let draftWaitSeconds: TimeInterval = 6
    static let pollSeconds: TimeInterval = 0.25
    /// Новое окно ещё без заголовка к сроку — ждём его заголовок ещё столько.
    static let untitledGraceSeconds: TimeInterval = 1
    /// Потолок поиска пункта по часам и срок AX на каждый элемент (правка критика V-N п. 11).
    static let searchSeconds: TimeInterval = 1
    static let axTimeout: Float = 0.25
    /// Прогрев «Нового окна» моложе этого — чужая цепочка ещё может родить окно «Code»
    /// (правка критика V-N п. 3): пустое окно не начинаем.
    static let newWindowQuietSeconds: TimeInterval = 40
    /// Действие команды черновику (контракт К18).
    static let draftSetupAction = "draft-setup"

    // MARK: - подписи

    /// Подписи пункта: запасная таблица плюс то, что нашлось в `Resources/*.json` бандла
    /// (только файлы верхнего уровня, не `.lproj`; до 2 МБ; словарь; строка по ключу).
    /// Порядок — запасные первыми, повторов нет.
    static func labels(resources: URL?, fileManager: FileManager = .default) -> [String] {
        var out = fallbackLabels
        var seen = Set(out)
        guard let resources = resources,
              let names = try? fileManager.contentsOfDirectory(atPath: resources.path) else { return out }
        for name in names.sorted() where name.hasSuffix(".json") {
            let url = resources.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue,
                  let size = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? NSNumber,
                  size.intValue <= maxTableBytes,
                  let data = try? Data(contentsOf: url),
                  let table = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let raw = table[messageKey] as? String else { continue }
            let label = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, seen.insert(label).inserted else { continue }
            out.append(label)
        }
        return out
    }

    /// Подписи с памятью: таблицы перечитываются, только когда сменился бандл или mtime
    /// `en-US.json` (Claude обновился).
    final class LabelCache {
        private var key: String?
        private var cached: [String] = []

        func labels(bundle: URL?, fileManager: FileManager = .default) -> [String] {
            let resources = bundle?.appendingPathComponent("Contents/Resources", isDirectory: true)
            let stamp = resources.flatMap {
                ProjectIndex.fileInfo(of: $0.appendingPathComponent("en-US.json"))?.modified
            }
            let key = "\(resources?.path ?? "")|\(stamp?.timeIntervalSinceReferenceDate ?? 0)"
            if key == self.key { return cached }
            self.key = key
            cached = BlankWindow.labels(resources: resources, fileManager: fileManager)
            return cached
        }
    }

    // MARK: - пункт в меню

    /// Пункт меню глазами поиска: заголовок и `AXEnabled` (nil — атрибута нет).
    typealias MenuTitle = (title: String, enabled: Bool?)

    /// Порядок меню-бара для поиска: сперва File (третий ребёнок — после меню Apple и меню
    /// приложения), потом остальные по порядку (правка критика V-N п. 11).
    static func searchOrder(count: Int) -> [Int] {
        guard count > 2 else { return Array(0..<max(count, 0)) }
        return [2] + (0..<count).filter { $0 != 2 }
    }

    /// Номер пункта с подписью ЦЕЛИКОМ (обрезка пробелов) и не выключенного. «New Session»
    /// без хвоста — другой пункт Claude, его не берём.
    static func match(_ items: [MenuTitle], labels: Set<String>) -> Int? {
        items.firstIndex { item in
            item.enabled != false
                && labels.contains(item.title.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Поиск по дереву заголовков: меню-бар → меню → пункты. Чистая часть живого поиска.
    static func find(in tree: [[MenuTitle]], labels: [String]) -> (menu: Int, item: Int)? {
        let wanted = Set(labels)
        for menu in searchOrder(count: tree.count) {
            if let item = match(tree[menu], labels: wanted) { return (menu, item) }
        }
        return nil
    }

    // MARK: - черновик

    static func isDraftTitle(_ title: String) -> Bool {
        draftTitles.contains(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    /// Что делать на опросе: окна не из `before`. Черновик берём, только когда кандидат «Code»
    /// РОВНО один (правка критика V-N п. 3): два — чужая цепочка тоже родила «Code», и гадать
    /// нельзя. Заголовок проверяется на каждом опросе, и окно с чужим заголовком не выбывает
    /// (п. 4): до `document.title` черновик зовётся «Claude», «» или «about:blank».
    enum Poll: Equatable {
        case take(PimpWindow)
        case wait
        case missing
    }

    static func poll(fresh: [PimpWindow], elapsed: TimeInterval) -> Poll {
        let drafts = fresh.filter { isDraftTitle($0.title) }
        if drafts.count == 1 { return .take(drafts[0]) }
        guard elapsed >= draftWaitSeconds else { return .wait }
        // Срок вышел, а новое окно ещё без заголовка — даём ему заголовок получить.
        let untitled = drafts.isEmpty && fresh.contains {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if untitled, elapsed < draftWaitSeconds + untitledGraceSeconds { return .wait }
        return .missing
    }

    // MARK: - команда черновику (К18)

    /// Модель и ступень пустого окна — как у последнего чата папки; Auto или чата нет —
    /// полей нет (🔘 V-N 4).
    static func model(of session: SessionModel?) -> (model: String?, effort: String?) {
        guard let session = session, !session.auto else { return (nil, nil) }
        return (session.menuModel, session.menuEffort)
    }

    /// Поля `draft-setup` по порядку контракта: `scope, title, draft, folder?, model?, effort?,
    /// text?, mode?`. Заголовок пустой — страница берёт окно в фокусе (черновик поднят перед этим).
    static func draftSetupFields(folder: String?, model: String?, effort: String?,
                                 text: String? = nil, bypass: Bool = false) -> [(key: String, value: CommandValue)] {
        var fields: [(key: String, value: CommandValue)] = [
            (key: "scope", value: .string(MenuModel.themeScopeWindow)),
            (key: "title", value: .string("")),
            (key: "draft", value: .bool(true)),
        ]
        if let folder = folder, !folder.isEmpty { fields.append((key: "folder", value: .string(folder))) }
        if let model = model, !model.isEmpty { fields.append((key: "model", value: .string(model))) }
        if let effort = effort, !effort.isEmpty { fields.append((key: "effort", value: .string(effort))) }
        if let text = text, !text.isEmpty { fields.append((key: "text", value: .string(text))) }
        // WF126 (поправка критика 5): режим — последним, только при включённом «Bypass в новых чатах».
        if bypass { fields.append((key: "mode", value: .string(BypassNew.draftMode))) }
        return fields
    }
}
