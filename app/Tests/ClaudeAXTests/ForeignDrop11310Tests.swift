import AppKit
import XCTest
@testable import ClaudeAX

/// #11310: картинка, брошенная из Telegram (Qt — байты картинки без файла), ложится в поле окна Claude.
final class ForeignDrop11310Tests: XCTestCase {
    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10, 0x4A, 0x46, 0x49, 0x46, 0, 1])
    private let claude: pid_t = 500
    private let telegram: pid_t = 700

    private func info(pid: pid_t, id: UInt32, frame: CGRect, layer: Int = 0, alpha: Double = 1) -> WindowInfo {
        WindowInfo([kCGWindowOwnerPID as String: NSNumber(value: pid),
                    kCGWindowNumber as String: NSNumber(value: id),
                    kCGWindowLayer as String: NSNumber(value: layer),
                    kCGWindowAlpha as String: NSNumber(value: alpha),
                    kCGWindowBounds as String: frame.dictionaryRepresentation as NSDictionary])!
    }

    private func tiff() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.tiffRepresentation!
    }

    // MARK: - чистая часть

    /// Что кладёт Telegram Desktop: TIFF от `setImageData`, исходный JPEG своим типом Qt, служебные типы — без файла.
    func testTelegramDragGivesOriginalJPEG() throws {
        let types = ["com.trolltech.qt.MimeTypeName", "public.tiff", "com.trolltech.anymime.image--jpeg",
                     "com.trolltech.anymime.application--x-td-use-jpeg"]
        var asked: [String] = []
        let picked = try XCTUnwrap(ForeignDrop.pick(types: types) { type in
            asked.append(type)
            return type == "public.tiff" ? self.tiff() : type.hasSuffix("image--jpeg") ? self.jpeg : Data("1".utf8)
        })
        XCTAssertEqual(picked, ForeignDrop.Picked(data: jpeg, ext: "jpg"))
        XCTAssertFalse(asked.contains("com.trolltech.qt.MimeTypeName"), "чужие типы броска не читаем")
    }

    func testOnlyTIFFBecomesPNG() throws {
        let picked = try XCTUnwrap(ForeignDrop.pick(types: ["public.tiff"]) { _ in self.tiff() })
        XCTAssertEqual(picked.ext, "png")
        XCTAssertEqual(ForeignDrop.sniff(picked.data), "png")
    }

    /// Бросок с файлом (Finder, документ Telegram) Chromium берёт сам — мимо; текст без картинки — мимо.
    func testFileOrTextDragIsNotOurs() {
        XCTAssertNil(ForeignDrop.pick(types: ["public.file-url", "public.png"]) { _ in self.jpeg })
        XCTAssertNil(ForeignDrop.pick(types: ["NSFilenamesPboardType", "public.tiff"]) { _ in self.tiff() })
        XCTAssertNil(ForeignDrop.pick(types: ["public.utf8-plain-text"]) { _ in Data("hi".utf8) })
        XCTAssertNil(ForeignDrop.pick(types: ["public.png"]) { _ in Data("not image".utf8) })
    }

    func testSniff() {
        XCTAssertEqual(ForeignDrop.sniff(jpeg), "jpg")
        XCTAssertEqual(ForeignDrop.sniff(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])), "png")
        XCTAssertEqual(ForeignDrop.sniff(Data("RIFF\0\0\0\0WEBP".utf8)), "webp")
        XCTAssertEqual(ForeignDrop.sniff(Data("GIF89a".utf8)), "gif")
        XCTAssertNil(ForeignDrop.sniff(Data()))
    }

    func testWindowAtPointIsFrontmostVisibleLayerZero() {
        let list = [info(pid: 1, id: 9, frame: CGRect(x: 0, y: 0, width: 2000, height: 2000), layer: 25),
                    info(pid: claude, id: 3, frame: CGRect(x: 0, y: 0, width: 50, height: 50), alpha: 0),
                    info(pid: telegram, id: 4, frame: CGRect(x: 0, y: 0, width: 300, height: 300)),
                    info(pid: claude, id: 5, frame: CGRect(x: 0, y: 0, width: 1000, height: 800))]
        XCTAssertEqual(ForeignDrop.window(at: CGPoint(x: 10, y: 10), in: list)?.id, 4)
        XCTAssertEqual(ForeignDrop.window(at: CGPoint(x: 500, y: 500), in: list)?.id, 5)
        XCTAssertNil(ForeignDrop.window(at: CGPoint(x: 5000, y: 5000), in: list))
    }

    func testFileName() {
        let at = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(ForeignDrop.fileName(source: "Telegram", at: at, ext: "jpg").hasPrefix("Telegram "))
        XCTAssertTrue(ForeignDrop.fileName(source: "a/b:c", at: at, ext: "png").hasPrefix("abc "))
        XCTAssertTrue(ForeignDrop.fileName(source: nil, at: at, ext: "png").hasSuffix(".png"))
    }

    // MARK: - сторож

    private final class Rig {
        var down = true
        var count = 10
        var point = CGPoint(x: 100, y: 100)
        var reads = 0
        var data: ForeignDrop.Picked? = ForeignDrop.Picked(data: Data([0xFF, 0xD8, 0xFF]), ext: "jpg")
        var queued: [() -> Void] = []
        var dropped: [(CGWindowID, ForeignDrop.Picked)] = []
    }

    private func make(_ rig: Rig) -> ForeignDrop {
        let drop = ForeignDrop()
        let tg = info(pid: telegram, id: 4, frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        let cl = info(pid: claude, id: 7, frame: CGRect(x: 400, y: 0, width: 600, height: 800))
        drop.claudePID = { self.claude }
        drop.buttonDown = { rig.down }
        drop.dragCount = { rig.count }
        drop.cursor = { rig.point }
        drop.windows = { [tg, cl] }
        drop.read = { rig.reads += 1; return rig.data }
        drop.schedule = { _, block in rig.queued.append(block) }
        drop.onDrop = { id, picked, _ in rig.dropped.append((id, picked)) }
        return drop
    }

    private func step(_ rig: Rig) {
        let jobs = rig.queued
        rig.queued = []
        jobs.forEach { $0() }
    }

    /// Нажал в Telegram, потащил (счётчик доски сменился), над Claude прочитали один раз, отпустил — в поле окна 7.
    func testDragFromTelegramToClaudeDelivers() {
        let rig = Rig()
        let drop = make(rig)
        drop.pressed()
        step(rig)
        rig.count = 11
        step(rig)
        XCTAssertEqual(rig.reads, 0, "над Telegram ещё не читаем")
        rig.point = CGPoint(x: 600, y: 300)
        step(rig)
        step(rig)
        XCTAssertEqual(rig.reads, 1, "прочитали в полёте один раз")
        rig.down = false
        step(rig)
        XCTAssertEqual(rig.dropped.map { $0.0 }, [7])
        XCTAssertNil(drop.press)
        XCTAssertTrue(rig.queued.isEmpty, "после отпускания опрос стоит")
    }

    func testReleaseOutsideClaudeOrPlainClickDoesNothing() {
        let rig = Rig()
        let drop = make(rig)
        // Простой щелчок: доска перетаскивания не менялась.
        drop.pressed()
        rig.point = CGPoint(x: 600, y: 300)
        rig.down = false
        step(rig)
        XCTAssertTrue(rig.dropped.isEmpty)
        XCTAssertEqual(rig.reads, 0)
        // Перетащил, но отпустил над Telegram.
        rig.point = CGPoint(x: 100, y: 100)
        rig.down = true
        drop.pressed()
        rig.count = 12
        rig.down = false
        step(rig)
        XCTAssertTrue(rig.dropped.isEmpty)
    }

    /// Перетаскивание из самого Claude (плитка, картинка ленты) — не наше: страница справляется сама.
    func testDragFromClaudeItselfIsIgnored() {
        let rig = Rig()
        let drop = make(rig)
        rig.point = CGPoint(x: 600, y: 300)
        drop.pressed()
        XCTAssertNil(drop.press)
        XCTAssertTrue(rig.queued.isEmpty)
    }

    /// Быстрый бросок: в полёте над Claude не побывали — читаем на отпускании; картинки нет — ничего.
    func testFastDropReadsOnReleaseAndNoImageMeansNothing() {
        let rig = Rig()
        let drop = make(rig)
        drop.pressed()
        rig.count = 11
        rig.point = CGPoint(x: 600, y: 300)
        rig.down = false
        step(rig)
        XCTAssertEqual(rig.dropped.count, 1)
        rig.data = nil
        rig.point = CGPoint(x: 100, y: 100)
        rig.down = true
        drop.pressed()
        rig.count = 12
        rig.point = CGPoint(x: 600, y: 300)
        step(rig)
        rig.down = false
        step(rig)
        XCTAssertEqual(rig.dropped.count, 1)
    }

    /// Настоящая доска (своя, не системная доска перетаскивания) с типами Telegram — `read` по ней.
    func testRealPasteboardWithTelegramTypes() throws {
        let board = NSPasteboard(name: NSPasteboard.Name("pimp-test-11310-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        let item = NSPasteboardItem()
        item.setData(tiff(), forType: .tiff)
        item.setData(jpeg, forType: NSPasteboard.PasteboardType("com.trolltech.anymime.image--jpeg"))
        board.writeObjects([item])
        let picked = ForeignDrop.pick(types: (board.types ?? []).map { $0.rawValue }) {
            board.data(forType: NSPasteboard.PasteboardType($0))
        }
        XCTAssertEqual(picked?.ext, "jpg")
    }
}
