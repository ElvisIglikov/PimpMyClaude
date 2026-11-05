import AppKit
import CoreGraphics
import Foundation

/// «Картинку из Telegram — бросок в окно Claude» (#11310, слово Элвиса 31.10 ~02:45: «Я вот с Telegram беру картинку,
/// перетаскиваю dragdrop в окно клауда. Она же должна вставляться»).
///
/// Где рвалось: Telegram Desktop (Qt, `com.tdesktop.Telegram`) кладёт в перетаскивание фото не файл, а сами байты
/// картинки — `QMimeData::setImageData` (`public.tiff`) и `image/jpeg` (`com.trolltech.anymime.image--jpeg`), без
/// `public.file-url` (tdesktop `history_view_drag.cpp`, `FillDragMimeWithPhoto`). Chromium на macOS из броска берёт
/// только файлы по путям, адреса, текст и HTML — байты картинки и файловые обещания (Фото, Почта) в `drop` не попадают:
/// `dataTransfer.files` пуст, страница не получает ничего, и бросок «отъезжает» назад.
///
/// Починка на стороне Пимпа: нажатие мыши в чужом приложении (глобальный монитор `leftMouseDown`, без прав
/// Универсального доступа) — короткий опрос, пока кнопка зажата. Перетаскивание началось (счётчик доски `.drag`
/// сменился), картинка без файла, курсор над окном Claude — байты читаются СРАЗУ, пока источник жив (Qt отдаёт данные
/// перетаскивания лениво и после броска их не держит). Кнопку отпустили над окном Claude — картинка ложится файлом
/// во временный каталог и в поле этого окна тем же путём, что фото с AirDrop: буфер, окно вперёд, ⌘V
/// (`ClaudeActions.paste`). Страница принимает её обычной вставкой — с номером «Скриншот N» и сверкой дубля (К-ATTACH-DUP).
/// Бросок с файлом (Finder, документ из Telegram) не трогаем: его Chromium принимает сам.
public final class ForeignDrop {
    /// Шаг опроса, пока кнопка зажата.
    static let pollSeconds: TimeInterval = 0.05
    /// Больше — не картинка из чата, а что-то странное: не возим.
    static let maxBytes = 40 * 1024 * 1024
    /// Временные файлы бросков старше этого убираются при следующем броске.
    static let keepSeconds: TimeInterval = 3600
    static let noticeSeconds: TimeInterval = 4

    /// Типы, при которых бросок — с файлом, и Chromium возьмёт его сам.
    static let fileTypes: Set<String> = ["public.file-url", "NSFilenamesPboardType"]

    /// Картинка из доски перетаскивания: байты и расширение файла.
    struct Picked: Equatable {
        let data: Data
        let ext: String
    }

    // MARK: - чистая часть

    /// Расширение по первым байтам; не знакомый формат — nil.
    static func sniff(_ data: Data) -> String? {
        let head = [UInt8](data.prefix(12))
        if head.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if head.count >= 12, head.starts(with: [0x52, 0x49, 0x46, 0x46]), Array(head[8..<12]) == [0x57, 0x45, 0x42, 0x50] {
            return "webp"
        }
        if head.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "gif" }
        return nil
    }

    /// Тип доски похож на картинку (свои UTI, `image/…` Qt и браузеров).
    static func isImageType(_ type: String) -> Bool {
        let low = type.lowercased()
        return ["png", "jpeg", "jpg", "webp", "gif", "tiff", "heic", "image"].contains { low.contains($0) }
    }

    /// Только картинка без файла: в доске есть тип картинки и нет пути к файлу.
    static func wants(types: [String]) -> Bool {
        !types.contains(where: fileTypes.contains) && types.contains(where: isImageType)
    }

    /// Что вставлять. Сначала готовые JPEG/PNG/WebP/GIF как есть (у Telegram — исходный JPEG, он меньше TIFF), потом
    /// прочая картинка (TIFF, HEIC) — в PNG. Читаются только типы картинок: чужие данные броска не трогаем.
    static func pick(types: [String], data: (String) -> Data?) -> Picked? {
        guard wants(types: types) else { return nil }
        let images = types.filter(isImageType)
        var others: [Data] = []
        for type in images {
            guard let bytes = data(type), !bytes.isEmpty, bytes.count <= maxBytes else { continue }
            if let ext = sniff(bytes) { return Picked(data: bytes, ext: ext) }
            others.append(bytes)
        }
        for bytes in others {
            if let rep = NSBitmapImageRep(data: bytes), let png = rep.representation(using: .png, properties: [:]),
               png.count <= maxBytes {
                return Picked(data: png, ext: "png")
            }
        }
        return nil
    }

    /// Окно под точкой (координаты оконного сервера, верх-лево): первое спереди окно слоя 0, видимое.
    static func window(at point: CGPoint, in windows: [WindowInfo]) -> WindowInfo? {
        windows.first { $0.layer == 0 && $0.id > 0 && $0.alpha > 0.01 && $0.frame.contains(point) }
    }

    /// Имя файла броска: откуда и когда (страница всё равно назовёт картинку «Скриншот N»).
    static func fileName(source: String?, at date: Date, ext: String) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let clean = (source ?? "").components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined()
            .trimmingCharacters(in: .whitespaces)
        return "\(clean.isEmpty ? "Картинка" : clean) \(format.string(from: date)).\(ext)"
    }

    // MARK: - сторож

    /// Отдать картинку окну; `done(true)` — ⌘V нажат.
    var onDrop: ((CGWindowID, Picked, String?) -> Void)?
    var claudePID: () -> pid_t? = { nil }
    var buttonDown: () -> Bool = { NSEvent.pressedMouseButtons & 1 != 0 }
    var dragCount: () -> Int = { NSPasteboard(name: .drag).changeCount }
    var cursor: () -> CGPoint = { CGEvent(source: nil)?.location ?? .zero }
    var windows: () -> [WindowInfo] = { WindowInfo.list([.optionOnScreenOnly, .excludeDesktopElements]) }
    var read: () -> Picked? = {
        let board = NSPasteboard(name: .drag)
        return ForeignDrop.pick(types: (board.types ?? []).map { $0.rawValue }) { board.data(forType: NSPasteboard.PasteboardType($0)) }
    }
    var schedule: (TimeInterval, @escaping () -> Void) -> Void = { delay, block in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
    }

    /// Одно нажатие кнопки: счётчик доски на нажатии, кто источник, прочитанная картинка.
    struct Press {
        let count: Int
        let source: pid_t?
        var picked: Picked?
        var tried = false
    }

    public private(set) var running = false
    private var monitor: Any?
    private(set) var press: Press?

    func start() {
        guard !running else { return }
        running = true
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in self?.pressed() }
    }

    func stop() {
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        running = false
        press = nil
    }

    /// Нажатие в чужом приложении. Источник — Claude (своя плитка, картинка ленты): мимо, это не наш случай.
    func pressed() {
        guard press == nil else { return }
        let source = ForeignDrop.window(at: cursor(), in: windows())?.pid
        if let claude = claudePID(), source == claude { return }
        press = Press(count: dragCount(), source: source)
        schedule(ForeignDrop.pollSeconds) { [weak self] in self?.poll() }
    }

    /// Окно Claude под курсором; не Claude или Claude не запущен — nil.
    private func claudeWindow() -> CGWindowID? {
        guard let claude = claudePID(), let hit = ForeignDrop.window(at: cursor(), in: windows()), hit.pid == claude
        else { return nil }
        return hit.id
    }

    func poll() {
        guard var current = press else { return }
        guard buttonDown() else { return released() }
        if !current.tried, dragCount() != current.count, claudeWindow() != nil {
            current.tried = true
            current.picked = read()
            press = current
        }
        schedule(ForeignDrop.pollSeconds) { [weak self] in self?.poll() }
    }

    /// Кнопку отпустили: было перетаскивание картинки без файла и отпустили над окном Claude — отдаём.
    func released() {
        guard let current = press else { return }
        press = nil
        guard dragCount() != current.count, let target = claudeWindow() else { return }
        // Не успели прочитать в полёте (быстрый бросок) — пробуем сейчас: источник ещё может отдать данные.
        guard let picked = current.picked ?? (current.tried ? nil : read()) else { return }
        let source = current.source.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName }
        onDrop?(target, picked, source)
    }

    /// Каталог временных файлов бросков; старые убираются.
    static func directory() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PimpMyClaude-drops", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let old = Date().addingTimeInterval(-keepSeconds)
        for url in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let date = date, date < old { try? FileManager.default.removeItem(at: url) }
        }
        return dir
    }
}

extension ClaudeAXController {
    // MARK: - картинка из Telegram и прочих — броском в поле (#11310)

    func startForeignDrop() {
        if foreignDrop.onDrop == nil {
            foreignDrop.claudePID = { [weak self] in self?.app.pid }
            foreignDrop.onDrop = { [weak self] id, picked, source in self?.pasteForeignDrop(id, picked, source: source) }
        }
        foreignDrop.start()
    }

    /// Файл во временный каталог — и в поле окна тем же `ClaudeActions.paste`, что фото с AirDrop.
    private func pasteForeignDrop(_ id: CGWindowID, _ picked: ForeignDrop.Picked, source: String?) {
        let refuse: (String) -> Void = { [weak self] why in
            self?.hud.show("🖼 Картинку\(source.map { " из \($0)" } ?? "") не вставил: \(why)", seconds: ForeignDrop.noticeSeconds)
        }
        let url = ForeignDrop.directory().appendingPathComponent(ForeignDrop.fileName(source: source, at: Date(), ext: picked.ext))
        guard (try? picked.data.write(to: url, options: .atomic)) != nil else { return refuse("не записал файл") }
        actions.paste(into: id, paths: [url.path]) { pressed in
            if !pressed { refuse("окно Claude не встало вперёд") }
        }
    }
}
