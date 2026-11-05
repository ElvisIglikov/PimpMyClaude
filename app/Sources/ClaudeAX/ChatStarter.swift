import Foundation
import Patcher

// Стартер чата (WF242; слово Элвиса 11.10.2026: «нажимаешь анализ памяти, у тебя в Claude Code вставляется, там
// проведи анализ памяти… человек Enter нажимает… Это как стартер чата, только с нашими предопределёнными
// настройками… человек может настроить его под себя… у него в промпте это хранится»).
// Текст поручения — файл в `~/Library/Application Support/MyClaude/prompts/`: создаётся с умолчанием при первом
// нажатии, готовый не перезаписывается (как `Patcher.ensureConfig`) — человек правит его под себя. Лоадер и страница
// каталог не читают. Вставляет текст в поле ввода `ClaudeAXController.insertStarter` — той же командой `workflow`,
// что кнопка «🚀 Workflow»: страница вставляет и не отправляет.

public enum ChatStarter {
    public static let folderName = "prompts"
    public static let memoryFileName = "memory-analysis.md"
    /// Заметки прошлых разборов — их ведёт сама нейронка по просьбе из текста.
    public static let memoryNotesFileName = "memory-analysis-notes.md"

    public static var defaultDirectory: URL {
        CommandChannel.directory.appendingPathComponent(folderName, isDirectory: true)
    }

    /// Текст поручения «Анализ памяти» по умолчанию; пути — настоящие, чтобы нейронка нашла файлы без догадок.
    public static func memoryDefault(directory: URL) -> String {
        let prompt = directory.appendingPathComponent(memoryFileName).path
        let notes = directory.appendingPathComponent(memoryNotesFileName).path
        return """
        Проведи анализ памяти этого Мака и помоги её освободить.

        1. Сначала прочитай заметки прошлых разборов: \(notes) (файла нет — это первый разбор).
        2. Посмотри, что занимает память сейчас: `memory_pressure`, `sysctl vm.swapusage`, `vm_stat`, программы \
        по памяти (`ps -axm -o rss,comm | head -30`). Ничего не закрывай и не удаляй без моего «да».
        3. Скажи коротко и простыми словами: сколько занято, есть ли своп и растёт ли он, какие программы едят \
        больше всего и что можно закрыть без потерь — лишние вкладки браузера, мессенджеры, фоновые программы \
        в строке меню. HTML и картинки из чатов легче смотреть в PimpViewer, чем в браузере.
        4. Предложи списком, что закрыть; закрывай только то, на что я ответил «да».
        5. В конце допиши в файл заметок дату, что нашёл, что закрыли и что помогло — следующий разбор начнётся с них.

        Этот текст — файл \(prompt). Предложи мне настроить разбор под себя (короче, подробнее, \
        другие проверки) и по моему слову поправь этот файл: кнопка «Анализ памяти» в PMP вставит уже новый текст.
        """
    }

    /// Текст поручения «Анализ памяти»: файла нет — создаётся с умолчанием; есть — читается как есть, не
    /// перезаписывается. Пустой файл — умолчание (файл не трогаем). Каталог создать не вышло — ошибка.
    public static func memoryPrompt(directory: URL = defaultDirectory, fileManager: FileManager = .default) throws -> String {
        let url = directory.appendingPathComponent(memoryFileName)
        let standard = memoryDefault(directory: directory)
        if fileManager.fileExists(atPath: url.path) {
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? standard : text
        }
        try SupportFiles.write(Data((standard + "\n").utf8), to: url, fileManager: fileManager)
        return standard
    }
}
