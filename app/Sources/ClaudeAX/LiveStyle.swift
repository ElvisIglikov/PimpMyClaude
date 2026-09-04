import Foundation

/// Живой блок стилей в `~/Library/Application Support/MyClaude/claude.css` (решение 1 плана WF14).
///
/// Лоадер v6 вставляет этот файл как **user-origin** CSS (`insertCSS(text,{cssOrigin:"user"})`,
/// перечитывает по mtime раз в секунду), а user-правило с `!important` по каскаду бьёт даже
/// инлайн-стиль автора — поэтому и радиус неоновой рамки, и поля по бокам чинятся строками
/// в файле, без перепатча Claude у всей команды. `inject.js` и лоадер здесь НЕ трогаются.
///
/// Приложение владеет ровно ОДНИМ блоком между маркерами; всё остальное содержимое файла
/// (правила Элвиса и правила из бандла) сохраняется дословно.
///
/// Три точки записи, других не нужно: запуск приложения, конец «Поставить»/«Снять»
/// (`Patcher.installLiveFiles` копирует claude.css из бандла ЦЕЛИКОМ и затирает блок)
/// и обработчик ползунка «↔️ Поля по бокам».
enum LiveStyle {
    /// Маркеры — побайтно такие, каждый на своей строке.
    static let markerStart = "/* PimpMyClaude:auto */"
    static let markerEnd = "/* /PimpMyClaude:auto */"

    static let cssFileName = "claude.css"
    static let configFileName = "claude.json"
    /// Ключи живого `claude.json`: поля по бокам и необязательный радиус окна.
    static let sidePaddingKey = "sidePadding"
    static let frameRadiusKey = "frameRadius"

    /// Поля по бокам по умолчанию — 5 px (решение Элвиса 04.09, вопрос 4 макета).
    /// Та же цифра лежит в `Patcher.configDefaults`, `claude-patch/claude.json` и `DEFAULTS`
    /// в `patch-claude.mjs`: таргеты `ClaudeAX` и `Patcher` друг друга не видят.
    static let defaultSidePadding = 5
    /// Ширина окна по умолчанию — только чтобы создать `claude.json`, если его ещё нет;
    /// у существующего файла свои значения не трогаются (см. `merged`).
    static let defaultMinWindowWidth = 360
    /// Границы ползунка: дальше 24 px поля снова съедают окно, меньше нуля не бывает.
    static let minSidePadding = 0
    static let maxSidePadding = 24

    /// Радиус углов окна macOS: у Tahoe (26) ≈ 17 pt по кругу, но угол — сквиркл, ровно сидит 15, у 13–15 — 10–11 pt. Замер по альфа-каналу
    /// скриншота окна Элвиса (macOS 26.5). Рамка `#myclaude-window-frame` рисуется инлайн-стилем
    /// с радиусом 10 — отсюда «углы обрезаются неровно» (задача #5359).
    static let modernFrameRadius = 15
    static let legacyFrameRadius = 10
    static let modernMacOSVersion = 26
    /// Годные значения необязательного ключа `frameRadius`: мусор игнорируем.
    static let maxFrameRadius = 40

    // MARK: - чистая часть (её и гоняют тесты — диска не касается)

    static func clamp(_ value: Int) -> Int { min(max(value, minSidePadding), maxSidePadding) }

    /// Радиус по версии macOS. Если Apple снова сменит углы — лечится строкой в claude.css
    /// ВНЕ блока и ПОСЛЕ него либо ключом `frameRadius` в claude.json.
    static func frameRadius(majorVersion: Int) -> Int {
        majorVersion >= modernMacOSVersion ? modernFrameRadius : legacyFrameRadius
    }

    /// Тот же радиус, но с оглядкой на необязательный ключ `frameRadius` живого claude.json.
    static func frameRadius(config: String?, majorVersion: Int) -> Int {
        if let value = number(config, key: frameRadiusKey), (0...maxFrameRadius).contains(value) {
            return value
        }
        return frameRadius(majorVersion: majorVersion)
    }

    /// Пять строк блока с маркерами (порядок и текст — контракт п. 1 плана WF14).
    /// Две подстраховочные строки (`:root{--chat-gutter…}` и широкий `[class*="ps-[var(--chat"]`)
    /// ловят и старые классы Claude, и новые `--chat-column-gutter-*`: при следующей смене
    /// сборки поля не отвалятся целиком.
    static func block(padding: Int, radius: Int) -> String {
        let px = "\(padding)px"
        return """
        \(markerStart)
        #myclaude-window-frame{border-radius:\(radius)px !important}
        [class*="--chat-column-gutter-start"]{--chat-column-gutter-start:\(px) !important;\
        --chat-column-gutter-end:\(px) !important}
        [class*="ps-[var(--chat-gutter"],[class*="pe-[var(--chat-gutter"],\
        .epitaxy-transcript-width,.epitaxy-composer-width{padding-inline-start:\(px) !important;\
        padding-inline-end:\(px) !important;padding-left:\(px) !important;padding-right:\(px) !important}
        [class*="ps-[var(--chat"],[class*="pe-[var(--chat"]{padding-inline-start:\(px) !important;\
        padding-inline-end:\(px) !important}
        \(markerEnd)
        """
    }

    /// Блок в файл: есть оба маркера — заменяем содержимое МЕЖДУ ними на месте (порядок строк
    /// файла не меняется); маркеров нет — дописываем блок в КОНЕЦ (последний выигрывает при
    /// равной специфичности, а правило полей лоадер кладёт ПЕРЕД содержимым файла);
    /// маркеры битые или блок задвоился — старый мусор вырезаем от первого до последнего
    /// маркера и пишем блок в конец. Чужие строки за пределами блока сохраняются дословно.
    static func applying(block: String, to text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        // Хвост после последнего перевода строки — не строка файла; финальный \n добавим сами.
        if lines.last?.isEmpty == true { lines.removeLast() }
        let blockLines = block.components(separatedBy: "\n")
        let starts = lines.indices.filter { isMarker(lines[$0], markerStart) }
        let ends = lines.indices.filter { isMarker(lines[$0], markerEnd) }

        if starts.count == 1, ends.count == 1, starts[0] < ends[0] {
            lines.replaceSubrange(starts[0]...ends[0], with: blockLines)
        } else {
            if let first = (starts + ends).min(), let last = (starts + ends).max() {
                lines.removeSubrange(first...last)
            }
            while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
            lines += blockLines
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func isMarker(_ line: String, _ marker: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == marker
    }

    /// Значение целого ключа живого claude.json; файла нет, JSON битый или значение не число — nil.
    static func number(_ config: String?, key: String) -> Int? {
        guard let config = config,
              let root = try? JSONSerialization.jsonObject(with: Data(config.utf8)) as? [String: Any]
        else { return nil }
        return (root[key] as? NSNumber)?.intValue
    }

    /// Merge-запись `sidePadding`: разобрать JSON → поменять ОДИН ключ → записать теми же
    /// опциями, что `Patcher.ensureConfig` (`prettyPrinted + sortedKeys`, перевод строки в конце).
    /// Остальные ключи (`minWindowWidth`, `projectsRoot`) не теряются: у Элвиса в живом файле
    /// `minWindowWidth: 300`, а в репозитории 360 — обычная перезапись отняла бы у него ширину окна.
    /// **JSON не разобрался — возвращаем nil: файл не трогаем вовсе** (критик В8), иначе снесём
    /// чужие настройки. Файла нет (`nil`) — создаём из умолчаний.
    static func merged(config: String?, sidePadding: Int) -> String? {
        var root: [String: Any]
        if let config = config {
            let trimmed = config.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                root = [:]
            } else if let parsed = try? JSONSerialization.jsonObject(with: Data(config.utf8)) as? [String: Any] {
                root = parsed
            } else {
                return nil
            }
        } else {
            root = ["minWindowWidth": defaultMinWindowWidth]
        }
        root[sidePaddingKey] = clamp(sidePadding)
        // `withoutEscapingSlashes` сверх опций `ensureConfig`: без него путь `projectsRoot`
        // Элвиса превратился бы в «\/Users\/elvis\/…» — файл он правит руками.
        guard let data = try? JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text + "\n"
    }

    // MARK: - диск

    static var defaultDirectory: URL { CommandChannel.directory }

    /// Текущее значение для ползунка: `claude.json` (его читает лоадер и правит сам Элвис),
    /// иначе память приложения, иначе 5 (критик В7).
    static func currentSidePadding(directory: URL = LiveStyle.defaultDirectory,
                                   defaults: UserDefaults = .standard) -> Int {
        let config = try? String(contentsOf: directory.appendingPathComponent(configFileName),
                                 encoding: .utf8)
        if let value = number(config, key: sidePaddingKey) { return clamp(value) }
        if let remembered = defaults.object(forKey: sidePaddingKey) as? Int { return clamp(remembered) }
        return defaultSidePadding
    }

    /// Переписать блок в живом claude.css. Пишем ТОЛЬКО при реальном изменении текста: лишний
    /// `write` дёргает mtime, и лоадер переставляет CSS во всех страницах каждую секунду.
    @discardableResult
    static func writeBlock(padding: Int, directory: URL = LiveStyle.defaultDirectory,
                           majorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
        -> Bool {
        let url = directory.appendingPathComponent(cssFileName)
        let config = try? String(contentsOf: directory.appendingPathComponent(configFileName),
                                 encoding: .utf8)
        let radius = frameRadius(config: config, majorVersion: majorVersion)
        let old = try? String(contentsOf: url, encoding: .utf8)
        let new = applying(block: block(padding: clamp(padding), radius: radius), to: old ?? "")
        guard new != old else { return true }
        return CommandChannel.writeAtomic(url, new)
    }

    /// Merge-запись живого claude.json. Битый JSON не трогаем — только строка в NSLog.
    @discardableResult
    static func writeConfig(sidePadding: Int, directory: URL = LiveStyle.defaultDirectory) -> Bool {
        let url = directory.appendingPathComponent(configFileName)
        let old = try? String(contentsOf: url, encoding: .utf8)
        guard let new = merged(config: old, sidePadding: sidePadding) else {
            NSLog("PimpMyClaude: %@ не разобрался — sidePadding не записан", url.path)
            return false
        }
        guard new != old else { return true }
        return CommandChannel.writeAtomic(url, new)
    }

    /// Ползунок «↔️ Поля по бокам» сдвинули: блок в claude.css и `sidePadding` в claude.json.
    /// В `command.json` не пишем вовсе — очередь канала и примерка тем тут ни при чём; лоадер
    /// видит файлы опросом раз в секунду, поэтому «сразу, без применить» = до ~1 с.
    static func apply(sidePadding value: Int, directory: URL = LiveStyle.defaultDirectory,
                      defaults: UserDefaults = .standard) {
        let padding = clamp(value)
        defaults.set(padding, forKey: sidePaddingKey)
        writeBlock(padding: padding, directory: directory)
        writeConfig(sidePadding: padding, directory: directory)
    }

    /// Восстановить блок, ничего не меняя по смыслу: запуск приложения и конец «Поставить»/«Снять».
    static func refresh(directory: URL = LiveStyle.defaultDirectory) {
        // Патч ещё не ставили — папки MyClaude нет; заводить её тут незачем, это дело «Поставить».
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        writeBlock(padding: currentSidePadding(directory: directory), directory: directory)
    }
}
