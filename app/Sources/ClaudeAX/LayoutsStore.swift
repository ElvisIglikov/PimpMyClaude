import CoreGraphics
import Foundation

/// Одно место сохранённой раскладки: какой проект, какой чат, как окно называлось и какая
/// это была ячейка (план WF41, слова Элвиса 08.09: «раскладка помнит три вещи на место»).
struct LayoutCell: Equatable {
    /// Абсолютный путь папки проекта или "" — папки окна приложение не знало.
    let folder: String
    /// id чата (`local_…`) или `main` — главное окно Claude: его чат в раскладке не живёт,
    /// при возврате ему ставится только рамка.
    let chat: String
    /// Заголовок окна на момент записи: им же CLI называет то, чего вернуть не вышло.
    let title: String
    /// Номер ячейки в сетке раскладки; окно стояло не по сетке — nil (`"cell":null`).
    let cell: Int?
}

/// Сохранённая раскладка окон под своим именем («Утро», «Разбор»).
struct WindowLayout: Equatable {
    let name: String
    let at: Date
    let mode: ArrangeLayout.Mode
    let cells: [LayoutCell]
}

/// Раскладки проектов — файл `~/Library/Application Support/MyClaude/layouts.json`:
/// `{"version":1,"layouts":[{"name","at","mode","cells":[{"folder","chat","title","cell"}]}]}`
/// (контракт плана WF41, эталон `tests/fixtures/pimp/layouts.json` — его читают оба конца).
///
/// Устроен как `ProjectsStore`: свой URL (в тестах — песочница), атомарная запись, битый файл
/// значит пустой список (меню обязано остаться живым), лимит записей с вытеснением по `at`.
/// Лоадер этого файла не знает — он наш, как `projects.json` и `window-themes.json`.
///
/// Класс не потокобезопасен — живёт на главной очереди, как и всё остальное.
final class LayoutsStore {
    static let fileName = "layouts.json"
    /// Больше тридцати раскладок не держим: уступает самая старая по `at`.
    static let limit = 30
    /// Имя — как у своих тем, не длиннее 80 знаков.
    static let nameLimit = 80
    /// Чат главного окна в записи: его разговор меняется, а окно одно.
    static let mainChat = "main"
    static let versionKey = "version"
    static let layoutsKey = "layouts"
    static let version = 1
    /// Рядом с command.json (папку заводит патч, а если её нет — `writeAtomic`).
    static var defaultURL: URL { CommandChannel.directory.appendingPathComponent(fileName) }

    private let url: URL

    init(url: URL = LayoutsStore.defaultURL) { self.url = url }

    /// Всё, что записано, свежими вперёд. Файл битый — пустой список.
    func load() -> [WindowLayout] { LayoutsStore.parse(try? Data(contentsOf: url)) }

    /// Раскладка по имени (регистр не важен, как у своих тем).
    func layout(named name: String) -> WindowLayout? {
        LayoutsStore.matching(name: name, in: load())
    }

    /// Записать раскладку: имя занято — перезаписываем её, за лимитом уходит самая старая.
    @discardableResult
    func save(_ layout: WindowLayout) -> Bool {
        guard !LayoutsStore.clean(name: layout.name).isEmpty else { return false }
        return write(LayoutsStore.merge(layout, into: load()))
    }

    /// «🗑 Удалить» в меню; раскладки с таким именем нет — файл не трогаем.
    @discardableResult
    func delete(name: String) -> Bool {
        let stored = load()
        let list = LayoutsStore.without(name: name, in: stored)
        guard list.count != stored.count else { return false }
        return write(list)
    }

    private func write(_ list: [WindowLayout]) -> Bool {
        CommandChannel.writeAtomic(url, LayoutsStore.json(list))
    }

    // MARK: - чистая часть (её же гоняют тесты)

    static func clean(name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(nameLimit))
    }

    static func matching(name: String, in list: [WindowLayout]) -> WindowLayout? {
        let wanted = clean(name: name).lowercased()
        guard !wanted.isEmpty else { return nil }
        return list.first { clean(name: $0.name).lowercased() == wanted }
    }

    static func without(name: String, in list: [WindowLayout]) -> [WindowLayout] {
        let wanted = clean(name: name).lowercased()
        return list.filter { clean(name: $0.name).lowercased() != wanted }
    }

    /// Слить свежую запись со старыми: имя занято — перезапись, порядок на выходе по `at`
    /// убыв., за лимитом уходит самая старая.
    static func merge(_ fresh: WindowLayout, into stored: [WindowLayout]) -> [WindowLayout] {
        let list = without(name: fresh.name, in: stored) + [fresh]
        return Array(list.sorted { $0.at > $1.at }.prefix(limit))
    }

    /// Снимок нынешней раскладки (план WF41): запись на каждое окно Claude. Номер ячейки —
    /// та рамка сетки, с которой окно совпало (допуск `ClaudeActions.frameTolerance`), иначе
    /// nil: окно стоит не по сетке.
    ///
    /// Окно, чей чат приложение не знает (тумблер «🗂 Цвет по проекту» выключен или `probe.js`
    /// держит агент), в файл не идёт вовсе — его заголовок уходит в `unknown`, и записывать
    /// нельзя: «Вернуть эти чаты» вернуло бы не те чаты (#5455).
    static func snapshot(name: String, at: Date, mode: ArrangeLayout.Mode, windows: [PimpWindow],
                         cells: [CGRect],
                         isMain: (String) -> Bool) -> (layout: WindowLayout, unknown: [String]) {
        var records: [LayoutCell] = []
        var unknown: [String] = []
        var mainTaken = false
        for window in windows {
            let main = isMain(window.title)
            guard main || !window.chat.isEmpty else {
                unknown.append(window.title)
                continue
            }
            // Главным окном приложение может назвать ДВА окна разом: второе записалось бы
            // как `main`, чат его пропал бы, а при возврате одно окно вставало бы в две
            // ячейки (#5729). Ведём себя как при неизвестном чате — запись отменяется целиком.
            //
            // Корень (#5534) починен: `ProjectPaint.stubKey` разбирает заглушку «Claude» по
            // карте probe. Но проверка остаётся, и снимать её нельзя: без карты (тумблер
            // выключен и круг не приехал, канал занял агент) заглушка снова значит `main`
            // у обоих окон, а окно без AX-заголовка зовётся главным всегда
            // (`windowKey(forTitle: "")` — ключ `main`).
            if main {
                guard !mainTaken else {
                    unknown.append(window.title)
                    continue
                }
                mainTaken = true
            }
            records.append(LayoutCell(folder: window.folder,
                                      chat: main ? mainChat : window.chat,
                                      title: window.title,
                                      cell: cell(of: window.frame, in: cells)))
        }
        return (WindowLayout(name: clean(name: name), at: at, mode: mode, cells: records), unknown)
    }

    /// Имя раскладки, которое приложение предлагает само (#5769, слово Элвиса 08.09: «Не надо
    /// имя раскладки. Ты же знаешь, что за проекты? Там и пиши в имени, типа имена проектов»):
    /// папки окон СЛЕВА НАПРАВО, без повторов и без пустых. Одна — «PimpMyClaude», две —
    /// «PimpMyClaude и VkusnoffKz», три — «A, B и C», больше трёх или длиннее `nameLimit` —
    /// «A, B и ещё 2». Прозвищ у папок нет: имя папки как есть.
    ///
    /// Порядок задаёт `ArrangeLayout.order` — тот же, что у «Расставить»: список окон приходит
    /// из `CGWindowList`, а он идёт по слоям, не по экрану.
    static func suggestedName(for windows: [PimpWindow]) -> String {
        var names: [String] = []
        for index in ArrangeLayout.order(of: windows.map { $0.frame }) {
            let folder = windows[index].folder.trimmingCharacters(in: .whitespaces)
            let name = folder.isEmpty
                ? ""
                : URL(fileURLWithPath: folder).lastPathComponent
                    .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !names.contains(name) else { continue }
            names.append(name)
        }
        guard let first = names.first else { return "" }
        guard names.count > 1 else { return clean(name: first) }
        let full = names.dropLast().joined(separator: ", ") + " и " + names[names.count - 1]
        guard names.count > 3 || full.count > nameLimit else { return full }
        // Больше трёх папок в имя не влезает: называем две и считаем остальные.
        guard names.count > 2 else { return clean(name: full) }
        return clean(name: "\(first), \(names[1]) и ещё \(names.count - 2)")
    }

    /// Ячейка окна: первая рамка сетки, совпавшая с рамкой окна (допуск 2 pt — тот же, с
    /// которым `setFrame` считает, что окно доехало).
    static func cell(of frame: CGRect, in cells: [CGRect]) -> Int? {
        cells.firstIndex { ClaudeActions.frameMatches($0, frame) }
    }

    /// Сколько мест раскладки получили номер ячейки. Ноль — окна стояли не по сетке, и
    /// записывать нечего: вернулось бы ноль окон (#5728). Это же число ответ зовёт `cells`.
    static func placedCells(_ layout: WindowLayout) -> Int {
        layout.cells.filter { $0.cell != nil }.count
    }

    /// Запись без имени или без мест пропускается — из-за одной кривой строки не должен
    /// пропасть весь файл. Незнакомая раскладка читается как лента, нечитаемое `at` — «давно».
    static func parse(_ data: Data?) -> [WindowLayout] {
        guard let data = data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root[layoutsKey] as? [[String: Any]] else { return [] }
        var out: [WindowLayout] = []
        var seen = Set<String>()
        for item in list {
            let name = clean(name: (item["name"] as? String) ?? "")
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { continue }
            let mode = (item["mode"] as? String).flatMap(ArrangeLayout.Mode.init(rawValue:)) ?? .ribbon
            let at = (item["at"] as? String).flatMap(PimpChannel.date) ?? .distantPast
            let cells = (item[layoutCellsKey] as? [[String: Any]]) ?? []
            out.append(WindowLayout(name: name, at: at, mode: mode,
                                    cells: cells.compactMap(parseCell)))
        }
        return out.sorted { $0.at > $1.at }
    }

    static let layoutCellsKey = "cells"

    /// Место без чата вернуть нечем — такую запись пропускаем.
    private static func parseCell(_ item: [String: Any]) -> LayoutCell? {
        let chat = ((item["chat"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
        guard !chat.isEmpty else { return nil }
        let cell = (item["cell"] as? NSNumber)?.intValue
        return LayoutCell(folder: ((item["folder"] as? String) ?? "")
                            .trimmingCharacters(in: .whitespaces),
                          chat: chat,
                          title: ((item["title"] as? String) ?? "")
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                          cell: (cell.map { $0 >= 0 } == true) ? cell : nil)
    }

    /// Порядок ключей побайтно: version, layouts; в записи — name, at, mode, cells;
    /// в месте — folder, chat, title, cell (эталон `tests/fixtures/pimp/layouts.json`).
    static func json(_ list: [WindowLayout]) -> String {
        let items = list.map { layout in
            CommandValue.object([
                (key: "name", value: .string(layout.name)),
                (key: "at", value: .string(PimpChannel.stampText(layout.at))),
                (key: "mode", value: .string(layout.mode.rawValue)),
                (key: layoutCellsKey, value: .array(layout.cells.map { cell in
                    .object([
                        (key: "folder", value: .string(cell.folder)),
                        (key: "chat", value: .string(cell.chat)),
                        (key: "title", value: .string(cell.title)),
                        (key: "cell", value: cell.cell.map { CommandValue.number($0) } ?? .null),
                    ])
                })),
            ]).json
        }
        return "{\"\(versionKey)\":\(version),\"\(layoutsKey)\":[" + items.joined(separator: ",") + "]}"
    }
}
