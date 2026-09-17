import AppKit
import Foundation

/// «📋 Копировать в буфер» (WF69, задача #6236; слово Элвиса 17.09.2026: «правой кнопкой нажать
/// „копировать в буфер“ — сам файл скопирует, потом в Telegram „вставить“ — и он вставит файл;
/// а то приходится Finder открывать»).
///
/// Страница Claude умеет положить в буфер только текст; ФАЙЛ (`public.file-url`, как «Скопировать»
/// в Finder) кладёт это приложение. Договор с `inject.js` (раздел 12г, `copyFileToClipboard`) —
/// побайтно: текстом в буфере лежит путь, а в HTML-слое — метка
/// `<!--pimpmyclaude:copy-file:<путь в percent-encoding>-->` и ссылка file://. Слежка — раз в
/// 0,25 с по `changeCount` буфера (сам счётчик читается без данных); данные читаются, только когда
/// в буфере есть HTML-слой. Нашли метку и файл на диске — содержимое буфера заменяется файлом:
/// `public.file-url` + `NSFilenamesPboardType` + путь строкой (так вставка в терминал даёт путь,
/// а в Telegram и Finder — файл). Своя запись поднимает `changeCount` — она без метки, и тик её
/// пропускает. Приложения нет — в буфере остаётся путь: вставка даёт его текстом, не тишину.
///
/// На macOS 26 первое чтение данных буфера не по ⌘V спрашивает разрешение «PimpMyClaude хочет
/// прочитать буфер» — «Всегда разрешать» один раз; `changeCount` и `types` вопроса не поднимают.
public final class CopyFileRelay {
    public static let markStart = "<!--pimpmyclaude:copy-file:"
    public static let markEnd = "-->"
    public static let interval: TimeInterval = 0.25
    /// Старый тип Finder: его до сих пор читают приложения, не знающие `public.file-url`.
    public static let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    /// Файл лёг в буфер — имя файла для плашки.
    public var onCopied: ((String) -> Void)?
    /// Метка есть, а файла на диске нет — путь из метки; буфер не трогаем.
    public var onMissing: ((String) -> Void)?
    public private(set) var copies = 0
    public private(set) var misses = 0

    private let pasteboard: NSPasteboard
    private let exists: (String) -> Bool
    private var lastChangeCount: Int
    private var timer: Timer?

    public init(pasteboard: NSPasteboard = .general,
                exists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.pasteboard = pasteboard
        self.exists = exists
        lastChangeCount = pasteboard.changeCount
    }

    public func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// `copy=<положил>/<метка без файла>` для строки диагностики.
    public var status: String { "\(copies)/\(misses)" }

    /// Путь из HTML-слоя буфера; nil — метки нет (обычная копия), метка битая или путь не абсолютный.
    public static func path(inHTML html: String) -> String? {
        guard let start = html.range(of: markStart) else { return nil }
        let rest = html[start.upperBound...]
        guard let end = rest.range(of: markEnd) else { return nil }
        let encoded = String(rest[..<end.lowerBound])
        guard !encoded.isEmpty, let path = encoded.removingPercentEncoding, path.hasPrefix("/") else { return nil }
        return path
    }

    /// Один тик: счётчик не менялся — ничего не читаем. Вернул путь — файл лёг в буфер.
    @discardableResult
    public func tick() -> String? {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return nil }
        lastChangeCount = count
        guard pasteboard.types?.contains(.html) == true,
              let html = pasteboard.string(forType: .html),
              let path = Self.path(inHTML: html) else { return nil }
        guard exists(path) else {
            misses += 1
            onMissing?(path)
            return nil
        }
        guard Self.write(path: path, to: pasteboard) else { return nil }
        lastChangeCount = pasteboard.changeCount
        copies += 1
        onCopied?((path as NSString).lastPathComponent)
        return path
    }

    /// Файл в буфер тремя слоями одного элемента — как после «Скопировать» в Finder.
    @discardableResult
    public static func write(path: String, to pasteboard: NSPasteboard) -> Bool {
        let url = URL(fileURLWithPath: path)
        pasteboard.clearContents()
        let fileURL = pasteboard.setString(url.absoluteString, forType: .fileURL)
        let names = pasteboard.setPropertyList([path], forType: filenamesType)
        let text = pasteboard.setString(path, forType: .string)
        return fileURL && names && text
    }
}
