import Foundation
import Patcher

/// Комплект воркфлоу (решение 3 плана WF9): `resources/workflow-kit/{WORKFLOW.md,KICKOFF.md}`
/// лежит в бандле (`Contents/Resources/workflow-kit`, кладёт tools/bundle.sh) и копируется в
/// `~/Library/Application Support/MyClaude/workflow/`. Путь к WORKFLOW.md зашит в текст
/// KICKOFF.md — оркестратор в чате читает правила оттуда сам.
///
/// Копию кладут трое: «Пропатчить Claude» (Patcher.installLiveFiles), запуск новой сборки
/// (Patcher.refreshLiveFilesIfBundledNewer — только когда страница в бандле строго новее) и первый клик по пункту
/// «🚀 Workflow» — на случай, если патч ставили версией приложения без комплекта.
enum WorkflowKit {
    /// Папка комплекта в ресурсах .app.
    static let bundledFolderName = Patcher.workflowKitDirName
    /// Папка комплекта в Application Support (её имя знает текст KICKOFF.md).
    static let installedFolderName = Patcher.workflowDirName
    static let rulesName = "WORKFLOW.md"
    static let kickoffName = "KICKOFF.md"
    /// Короткий режим ответов (WF89): KICKOFF велит его прочитать, поэтому копируется вместе с правилами.
    static let styleName = "STYLE.md"
    static let files = [rulesName, styleName, kickoffName]

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

    /// Разложить комплект рядом с command.json — той же копией, что у патчера (`Patcher.copyWorkflowKit`).
    /// Возвращает false, если комплекта нет или хоть один файл не лёг — пункт меню всё равно шлёт команду:
    /// без правил чат хотя бы получит кикофф.
    @discardableResult
    static func install(from source: URL? = bundledDirectory, to target: URL = installedDirectory) -> Bool {
        guard let source = source,
              files.allSatisfy({ FileManager.default.fileExists(atPath: source.appendingPathComponent($0).path) })
        else { return false }
        return (try? Patcher.copyWorkflowKit(from: source, to: target)) != nil
    }
}
