import Foundation

/// Рик — житель Пимпа (WF216, #9381; слово Элвиса 10.10.2026: «когда люди устанавливают Пимпа, то у них и Рик
/// сразу появляется»). Комплект `resources/rick-kit` (снимок публичного RickBoss, откуда — `KIT-SOURCE.txt`) едет в
/// бандле (`Contents/Resources/rick-kit`, кладёт tools/bundle.sh) и копируется в `<projectsRoot>/Rick`.
///
/// Ставят двое: первый запуск новой установки (`AppDelegate`, тот же признак, что у умолчаний WF210) и строка
/// «Поставить Рика» в настройках панели. Правила одни: папка `Rick` уже есть (любая) — не трогаем ничего;
/// копирование сорвалось — своей недописанной папки не остаётся и `mainProject` не пишется. Сети нет, скрипты
/// комплекта (`install.sh`) приложение не запускает — первый шаг человеку говорит README комплекта.
public enum RickKit {
    /// Папка комплекта в ресурсах .app.
    static let bundledFolderName = "rick-kit"
    /// Папка Рика в корне проектов — она же значение `mainProject`.
    static let folderName = "Rick"

    public enum Outcome: Equatable {
        /// Комплект лёг в эту папку.
        case installed(URL)
        /// Папка уже была — ничего не тронуто.
        case exists(URL)
        /// Не вышло; текст — простыми словами, для строки в панели. На диске ничего не изменилось.
        case failed(String)
    }

    static var bundledDirectory: URL? {
        ThemeCatalog.resourcesDirectory?.appendingPathComponent(bundledFolderName, isDirectory: true)
    }

    /// Где Рик стоит или встанет: `<projectsRoot>/Rick` (`projectsRoot` из claude.json, нет ключа — `~/Projects`).
    public static var folder: URL { folder(root: StatusFeed.projectsRoot()) }

    static func folder(root: URL) -> URL { root.appendingPathComponent(folderName, isDirectory: true) }

    public static var isPresent: Bool { isPresent(folder) }

    /// Есть ли что-то по этому пути: папка, файл или ссылка (даже битая) — чужое не трогаем в любом виде.
    static func isPresent(_ url: URL) -> Bool { (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil }

    /// Поставить Рика живыми путями. `configDefaults` — чем начать `claude.json`, если его ещё нет
    /// (`Patcher.configDefaults`: таргет ClaudeAX патчер не видит, а `ensureConfig` готовый файл не дополняет).
    public static func install(configDefaults: [String: Any]) -> Outcome {
        install(from: bundledDirectory, root: StatusFeed.projectsRoot(),
                configURL: CommandChannel.directory.appendingPathComponent(StatusFeed.configFileName),
                configDefaults: configDefaults)
    }

    /// Первый запуск: ставим сами только на новой установке (`PanelColorTiles.isNewInstall` — снимок настроек до
    /// первой записи и `installed.json`); у тех, кто Пимп уже ставил, — nil и ни одного файла: им строка
    /// «Поставить Рика» в настройках панели.
    public static func firstRun(values: [String: Any], installed: Data?, configDefaults: [String: Any]) -> Outcome? {
        firstRun(values: values, installed: installed) { install(configDefaults: configDefaults) }
    }

    static func firstRun(values: [String: Any], installed: Data?, install: () -> Outcome) -> Outcome? {
        PanelColorTiles.isNewInstall(values: values, installed: installed) ? install() : nil
    }

    /// Копия идёт во временную папку рядом и встаёт на место одним переименованием: папки `Rick` либо нет, либо она
    /// целая. `copy` подменяют тесты (сбой посреди копирования).
    static func install(from source: URL?, root: URL, configURL: URL, configDefaults: [String: Any] = [:],
                        copy: (URL, URL) throws -> Void = { try FileManager.default.copyItem(at: $0, to: $1) })
        -> Outcome {
        let fm = FileManager.default
        let target = folder(root: root)
        if isPresent(target) { return .exists(target) }
        guard let source = source, fm.fileExists(atPath: source.appendingPathComponent("AGENTS.md").path) else {
            return .failed("в этой сборке Пимпа нет комплекта Рика")
        }
        let madeRoot = !fm.fileExists(atPath: root.path)
        let draft = root.appendingPathComponent(".\(folderName)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            try copy(source, draft)
            try fm.moveItem(at: draft, to: target)
        } catch {
            // Откат — только своё: черновик и корень проектов, если создали его сами и он пуст.
            try? fm.removeItem(at: draft)
            if madeRoot, (try? fm.contentsOfDirectory(atPath: root.path))?.isEmpty == true { try? fm.removeItem(at: root) }
            return .failed("не получилось записать в \(NSString(string: root.path).abbreviatingWithTildeInPath)")
        }
        writeMainProject(configURL: configURL, configDefaults: configDefaults)
        return .installed(target)
    }

    /// `mainProject: "Rick"` в claude.json — только если ключ не задан: чужой выбор главного проекта не меняем.
    /// Остальные ключи остаются (merge, как `LiveStyle.merged`); файл не разобрался — не трогаем вовсе.
    static func writeMainProject(configURL: URL, configDefaults: [String: Any]) {
        let old = try? Data(contentsOf: configURL)
        guard PimpChannel.mainProjectSetting(old) == nil else { return }
        var json = configDefaults
        if let old = old, !old.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) {
            guard let parsed = (try? JSONSerialization.jsonObject(with: old)) as? [String: Any] else {
                NSLog("PimpMyClaude: %@ не разобрался — mainProject не записан", configURL.path)
                return
            }
            json = parsed
        }
        json[PimpChannel.mainProjectKey] = folderName
        guard let data = try? JSONSerialization.data(
            withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return }
        CommandChannel.writeAtomic(configURL, text + "\n")
    }
}
