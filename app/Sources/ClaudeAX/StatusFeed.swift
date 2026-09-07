import CryptoKit
import Foundation

/// Сводка одного проекта: имя папки и сырой markdown его status.md.
struct StatusProject: Equatable {
    let name: String
    let text: String
}

/// Сводки проектов для подсказки полоски прогресса (решение 2 плана WF9). Страница файлов
/// не читает — приложение раз в 60 с (и при показе меню) обходит
/// `<projectsRoot>/*/{docs,audit,work}/status.md` и, когда содержимое изменилось, пишет команду
/// `{"id","action":"status","at","scope":"all","projects":[{"name","text"}]}`.
///
/// Сводка — единственная команда, которую пишет не Элвис, поэтому она обязана уступать дорогу
/// меню. Очередь `CommandChannel` (приоритет `.status`) делает это сама: сводка ждёт, пока
/// очередь опустеет, и пропадает, если пришла команда меню, — тогда хэш не запоминается
/// и она уедет на следующем тике.
final class StatusFeed {
    /// Опрос файлов.
    static let interval: TimeInterval = 60
    /// Не больше 6 КБ сжатого markdown на проект (лишнее отрезается с начала файла).
    static let limit = 6 * 1024
    /// Общий потолок команды — 32 КБ на все проекты вместе (критик п. 6 плана WF9).
    static let totalLimit = 32 * 1024
    static let configFileName = "claude.json"
    static let configKey = "projectsRoot"
    static let defaultProjectsRoot = "~/_ElvisProjects"
    static let statusFileName = "status.md"
    /// Где у проекта может лежать сводка — в этом порядке (первая найденная и идёт в команду).
    static let statusFolders = ["docs", "audit", "work"]

    private let commands: CommandChannel
    private var timer: Timer?
    /// Хэш последней посланной сводки: без изменений содержимого команда не повторяется.
    private var sentDigest: String?
    private var scanning = false

    private(set) var sentCount = 0
    private(set) var projectCount = 0

    init(commands: CommandChannel) { self.commands = commands }

    /// Таймер в `.common`: пока открыто меню на кнопке «Свернуть», runloop сидит в режиме
    /// отслеживания и `.default` не тикал бы.
    func start() {
        stop()
        let timer = Timer(timeInterval: StatusFeed.interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    var isRunning: Bool { timer != nil }

    /// Прочитать сводки и, если изменились, послать. Зовётся таймером и показом меню.
    func refresh() {
        guard !scanning else { return }
        let root = StatusFeed.projectsRoot()
        // Папки проектов нет — ничего не шлём (у Маши, Аллы и Дениса её и не будет).
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return }
        scanning = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let projects = StatusFeed.cap(StatusFeed.scan(root: root))
            DispatchQueue.main.async { self?.publish(projects) }
        }
    }

    private func publish(_ projects: [StatusProject]) {
        scanning = false
        projectCount = projects.count
        guard !projects.isEmpty else { return }
        let digest = StatusFeed.digest(projects)
        guard digest != sentDigest else { return }
        // Очередь канала сама пропустит вперёд команды меню. Вытеснили сводку — хэш не
        // запоминаем, и та же сводка уедет на следующем тике (через 60 с).
        commands.write(action: CommandChannel.statusAction,
                       fields: StatusFeed.fields(projects)) { [weak self] written in
            guard written else { return }
            self?.sentDigest = digest
            self?.sentCount += 1
        }
    }

    // MARK: - чистая часть (её же гоняют тесты)

    /// `projectsRoot` из claude.json; ключа нет — `~/_ElvisProjects`.
    static func projectsRoot(configURL: URL = CommandChannel.directory
        .appendingPathComponent(configFileName)) -> URL {
        let data = try? Data(contentsOf: configURL)
        let json = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        let raw = (json?[configKey] as? String)?.trimmingCharacters(in: .whitespaces)
        let path = (raw?.isEmpty == false ? raw! : defaultProjectsRoot)
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
    }

    /// Проекты — свежими вперёд (по времени правки status.md; одинаковое время — по имени);
    /// у проекта берётся первая найденная сводка из docs/audit/work. Текст сжимается
    /// (`compact`) и режется до 6 КБ с начала файла (`slice`) — решение E плана WF22.
    static func scan(root: URL, fileManager: FileManager = .default) -> [StatusProject] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: root.path) else { return [] }
        var found: [(project: StatusProject, date: Date)] = []
        for name in names.sorted() where !name.hasPrefix(".") {
            let project = root.appendingPathComponent(name, isDirectory: true)
            let candidates = statusFolders.map {
                project.appendingPathComponent($0, isDirectory: true)
                    .appendingPathComponent(statusFileName)
            }
            guard let url = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }),
                  let text = try? String(contentsOf: url, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let compacted = compact(text)
            guard !compacted.isEmpty else { continue }
            let date = (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            found.append((StatusProject(name: name, text: slice(compacted)), date ?? .distantPast))
        }
        // Свежие первыми: общий потолок 32 КБ достаётся живым проектам, а не голове алфавита.
        return found.sorted { left, right in
            left.date == right.date ? left.project.name < right.project.name : left.date > right.date
        }.map { $0.project }
    }

    /// Общий потолок команды (критик п. 6 плана WF9): проекты кладутся по порядку, пока
    /// команда целиком влезает в 32 КБ; хвост отбрасывается — полсводки в подсказке ни к чему.
    /// Не влез даже первый проект (сводка-гигант у одного проекта) — режем его текст.
    static func cap(_ projects: [StatusProject], limit: Int = totalLimit) -> [StatusProject] {
        var kept: [StatusProject] = []
        for project in projects {
            guard payloadSize(kept + [project]) <= limit else { break }
            kept.append(project)
        }
        guard kept.isEmpty, let first = projects.first else { return kept }
        var text = first.text
        while !text.isEmpty {
            let size = payloadSize([StatusProject(name: first.name, text: text)])
            guard size > limit else { break }
            // Экранирование раздувает текст (перевод строки — шесть байт), поэтому режем
            // не на разницу, а долей и повторяем; каждый проход строго короче предыдущего.
            let budget = min(text.utf8.count - 1, Int(Double(text.utf8.count * limit) / Double(size)))
            text = prefix(text, bytes: max(0, budget))
        }
        return text.isEmpty ? [] : [StatusProject(name: first.name, text: text)]
    }

    /// Размер команды с этими проектами в байтах; id и at — постоянной длины.
    static func payloadSize(_ projects: [StatusProject]) -> Int {
        CommandChannel.payload(action: CommandChannel.statusAction, fields: fields(projects),
                               id: "0000000000000-0000", at: Date(timeIntervalSince1970: 0))
            .utf8.count
    }

    /// Поля команды после id, action, at: scope, projects (контракт п. 2 плана WF9).
    static func fields(_ projects: [StatusProject]) -> [(key: String, value: CommandValue)] {
        let items = projects.map { project in
            CommandValue.object([
                (key: "name", value: .string(project.name)),
                (key: "text", value: .string(project.text)),
            ])
        }
        return [(key: "scope", value: .string(MenuModel.themeScopeAll)),
                (key: "projects", value: .array(items))]
    }

    /// Хэш содержимого, а не порядка: проекты едут свежими вперёд, и «потрогали файл» не должно
    /// слать ту же сводку заново — поэтому считаем по копии, отсортированной по имени.
    static func digest(_ projects: [StatusProject]) -> String {
        var hasher = SHA256()
        for project in projects.sorted(by: { $0.name < $1.name }) {
            hasher.update(data: Data(project.name.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: Data(project.text.utf8))
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Сжатие сводки перед отправкой (решение E плана WF22): в блоке Workflow остаются
    /// заголовок «N️⃣ Workflow …», «- о чём», «- шаги», строка времени «- ЧЧ:ММ → …» и строки
    /// ролей «- роль · …»; пустые строки и хвост «Сейчас:»/«Ждёт Элвиса:» выкидываются, шапка
    /// файла (имя, «обновлено», счётчики) остаётся целиком. Строки едут как есть — экранирование
    /// команды не трогаем.
    static func compact(_ text: String) -> String {
        var kept: [String] = []
        var inBlocks = false
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if isWorkflowHeading(trimmed) {
                inBlocks = true
                kept.append(line)
            } else if isTailLine(trimmed) {
                continue
            } else if !inBlocks || isBlockLine(trimmed) {
                kept.append(line)
            }
        }
        return kept.joined(separator: "\n")
    }

    /// Хвост сводки для Элвиса — полоске не нужен.
    static func isTailLine(_ line: String) -> Bool {
        line.hasPrefix("Сейчас:") || line.hasPrefix("Ждёт Элвиса")
    }

    /// Строка блока, которая едет: «- о чём…», «- шаги…», время «- 13:05 → …» и роль «- роль · …».
    static func isBlockLine(_ line: String) -> Bool {
        guard line.hasPrefix("- ") else { return false }
        let body = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
        if body.hasPrefix("о чём") || body.hasPrefix("шаги") { return true }
        return startsWithClock(body) || body.contains(" · ")
    }

    /// Начало строки времени: «13:05 → закончит…».
    static func startsWithClock(_ text: String) -> Bool {
        let head = Array(text.prefix(5))
        guard head.count == 5, head[2] == ":" else { return false }
        return [0, 1, 3, 4].allSatisfy { head[$0].isASCII && head[$0].isNumber }
    }

    /// Срез до 6 КБ по границе блоков «N️⃣ Workflow» — режем **с начала** файла: шапка остаётся,
    /// а из блоков едут последние (живое важнее истории; решение E плана WF22).
    /// Блоков нет вовсе или ни один не влез вместе с шапкой — режем по знакам с головы,
    /// чтобы не порвать UTF-8.
    static func slice(_ text: String, limit: Int = limit) -> String {
        guard text.utf8.count > limit else { return text }
        let lines = text.components(separatedBy: "\n")
        let starts = lines.indices.filter { isWorkflowHeading(lines[$0]) }
        guard let firstBlock = starts.first else { return prefix(text, bytes: limit) }
        let head = Array(lines[0..<firstBlock])
        // Блоки — диапазоны строк от заголовка до следующего заголовка.
        var blocks: [Range<Int>] = []
        for (index, start) in starts.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1] : lines.count
            blocks.append(start..<end)
        }
        let size: (Set<Int>) -> Int = { chosen in
            joinedSize(head + chosen.sorted().flatMap { Array(lines[blocks[$0]]) })
        }
        // Живые блоки (💭 ✋ 🛑 в заголовке) едут ВСЕГДА, сколько бы запланированных ни стояло
        // после них: на настоящем status.md идущий 22-й блок с 19 плановыми следом срез с
        // начала отрезал бы ровно его (хвост батча S, гейт WF22). Потом — хвост блоков подряд.
        var chosen = Set<Int>()
        for index in blocks.indices.reversed() where isLiveHeading(lines[blocks[index].lowerBound]) {
            if size(chosen.union([index])) <= limit { chosen.insert(index) }
        }
        for index in blocks.indices.reversed() where !chosen.contains(index) {
            guard size(chosen.union([index])) <= limit else { break }
            chosen.insert(index)
        }
        guard !chosen.isEmpty else { return prefix(text, bytes: limit) }
        return (head + chosen.sorted().flatMap { Array(lines[blocks[$0]]) }).joined(separator: "\n")
    }

    /// Живой блок: идёт, ждёт Элвиса или упал — то, ради чего сводку и шлют.
    static func isLiveHeading(_ line: String) -> Bool {
        isWorkflowHeading(line) && ["💭", "✋", "🛑"].contains { line.contains($0) }
    }

    /// Размер строк, склеенных переводом строки, в байтах.
    private static func joinedSize(_ lines: [String]) -> Int {
        guard !lines.isEmpty else { return 0 }
        return lines.reduce(lines.count - 1) { $0 + $1.utf8.count }
    }

    /// Начало блока: строка вроде «3️⃣ Workflow ✅ готово» — цифра-клавиша (или 🔟) с начала.
    static func isWorkflowHeading(_ line: String) -> Bool {
        var scalars = Array(line.trimmingCharacters(in: .whitespaces).unicodeScalars.prefix(2))
        guard let first = scalars.first else { return false }
        if first == "\u{1F51F}" { return true } // 🔟
        guard first.value >= 0x30, first.value <= 0x39, scalars.count > 1 else { return false }
        scalars.removeFirst()
        return scalars[0] == "\u{FE0F}" || scalars[0] == "\u{20E3}"
    }

    /// Обрезка по знакам, не по байтам: разрезанный посередине символ уехал бы в команду мусором.
    static func prefix(_ text: String, bytes limit: Int) -> String {
        var out = ""
        var count = 0
        for character in text {
            let size = String(character).utf8.count
            if count + size > limit { break }
            out.append(character)
            count += size
        }
        return out
    }
}
