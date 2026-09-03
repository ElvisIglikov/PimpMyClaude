import Foundation

/// Комплект воркфлоу (решение 3 плана WF9): `resources/workflow-kit/{WORKFLOW.md,KICKOFF.md}`
/// лежит в бандле (`Contents/Resources/workflow-kit`, кладёт tools/bundle.sh) и копируется в
/// `~/Library/Application Support/MyClaude/workflow/`. Путь к WORKFLOW.md зашит в текст
/// KICKOFF.md — оркестратор в чате читает правила оттуда сам.
///
/// Копию кладут двое: «Поставить» (Patcher.installLiveFiles) и первый клик по пункту
/// «🚀 Workflow» — на случай, если патч ставили версией приложения без комплекта.
enum WorkflowKit {
    /// Папка комплекта в ресурсах .app.
    static let bundledFolderName = "workflow-kit"
    /// Папка комплекта в Application Support (её имя знает текст KICKOFF.md).
    static let installedFolderName = "workflow"
    static let rulesName = "WORKFLOW.md"
    static let kickoffName = "KICKOFF.md"
    static let files = [rulesName, kickoffName]

    /// Ресурсы .app; PIMPMYCLAUDE_RESOURCES — та же подмена, что у патчера и каталога тем.
    static var bundledDirectory: URL? {
        ThemeCatalog.resourcesDirectory?.appendingPathComponent(bundledFolderName, isDirectory: true)
    }

    static var installedDirectory: URL {
        CommandChannel.directory.appendingPathComponent(installedFolderName, isDirectory: true)
    }

    /// Текст кикоффа — всегда из бандла: копию в Application Support мог поправить кто угодно,
    /// а в поле ввода должна попасть та редакция, что приехала со сборкой.
    static func kickoff(directory: URL? = bundledDirectory) -> String? {
        guard let url = directory?.appendingPathComponent(kickoffName),
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    /// Разложить комплект рядом с command.json. Возвращает false, если хоть один файл не лёг —
    /// пункт меню всё равно шлёт команду: без правил чат хотя бы получит кикофф.
    @discardableResult
    static func install(from source: URL? = bundledDirectory, to target: URL = installedDirectory) -> Bool {
        guard let source = source,
              (try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)) != nil
        else { return false }
        var ok = true
        for name in files {
            guard let data = try? Data(contentsOf: source.appendingPathComponent(name)),
                  (try? data.write(to: target.appendingPathComponent(name), options: .atomic)) != nil
            else { ok = false; continue }
        }
        return ok
    }
}
