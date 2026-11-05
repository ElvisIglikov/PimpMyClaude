import AppKit
import XCTest
@testable import ClaudeAX

/// Только чистая логика: раскладка «Расставить», клавиши PMP и формат command.json.
/// Живой AX (окна Claude, авто-Allow, popUp) проверяется руками на гейте.
final class ClaudeAXTests: XCTestCase {
    // Двенадцать команд, включая выключатель Авто-Allow (К3) и режим микрофона (К4).
    func testSkeleton() { XCTAssertEqual(ClaudeCommand.allCases.count, 12) }

    /// Экран для «Расставить» — тот, где стоят окна, а не тот, где активное окно (08.09):
    /// большинство центров, ничья — первый, ни одного попадания — первый (меню-бар).
    func testScreensPickFollowsWindows() {
        let laptop = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let tall = CGRect(x: -1060, y: -419, width: 1060, height: 1696)
        let onLaptop = CGRect(x: 10, y: 40, width: 700, height: 800)
        let onTall = CGRect(x: -900, y: 100, width: 500, height: 800)
        XCTAssertEqual(Screens.pick(screens: [laptop, tall], for: [onLaptop, onLaptop, onTall]), 0)
        XCTAssertEqual(Screens.pick(screens: [laptop, tall], for: [onTall, onTall, onLaptop]), 1)
        XCTAssertEqual(Screens.pick(screens: [laptop, tall], for: [onLaptop, onTall]), 0)
        XCTAssertEqual(Screens.pick(screens: [laptop, tall], for: []), 0)
        XCTAssertEqual(Screens.pick(screens: [laptop, tall], for: [CGRect(x: 5000, y: 5000, width: 10, height: 10)]), 0)
    }

    // MARK: - «Расставить»

    func testColumnsKeepOneRowWhileCellsAreWideEnough() {
        // 1920/4 = 480 ≥ 340 — четыре столбца во всю высоту, а не 2×2.
        XCTAssertEqual(ArrangeLayout.columns(count: 4, width: 1920), 4)
        XCTAssertEqual(ArrangeLayout.columns(count: 1, width: 1920), 1)
        // 1920/6 = 320 < 340 — столбец отбрасывается, появляется второй ряд.
        XCTAssertEqual(ArrangeLayout.columns(count: 6, width: 1920), 5)
        XCTAssertEqual(ArrangeLayout.columns(count: 8, width: 1000), 2)
    }

    func testFramesTileAreaWithoutGaps() {
        let area = CGRect(x: 100, y: 25, width: 1710, height: 1055)
        let cells = ArrangeLayout.frames(count: 5, in: area)
        XCTAssertEqual(cells.count, 5)
        XCTAssertEqual(cells[0].minX, area.minX)
        XCTAssertEqual(cells[4].maxX, area.maxX)
        for i in 1..<cells.count {
            XCTAssertEqual(cells[i].minX, cells[i - 1].maxX, "щель между ячейками \(i - 1) и \(i)")
            XCTAssertEqual(cells[i].height, area.height)
        }
        XCTAssertTrue(ArrangeLayout.frames(count: 0, in: area).isEmpty)
    }

    func testFramesFillRowsTopDown() {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let cells = ArrangeLayout.frames(count: 3, in: area) // 1000/3 = 333 < 340 → 2×2
        XCTAssertEqual(cells[0], CGRect(x: 0, y: 0, width: 500, height: 400))
        XCTAssertEqual(cells[1], CGRect(x: 500, y: 0, width: 500, height: 400))
        XCTAssertEqual(cells[2], CGRect(x: 0, y: 400, width: 500, height: 400))
    }

    /// «Главный по центру» (WF102, #7904, правка критика C6): семь окон на живом Одиссее
    /// (2560×720, зазор 2) встают ровно как `layouts-manual/rick7.py` — главный четвёртым,
    /// шириной в треть, по три окна с боков. Плиткой меню он не бывает.
    func testCenterLayoutPutsMainInTheMiddleThird() {
        let odyssey = CGRect(x: -800, y: -720, width: 2560, height: 720)
        let seven = ArrangeLayout.frames(count: 7, in: odyssey, mode: .center, minCellWidth: 220, gap: 2)
        XCTAssertEqual(seven.map { $0.minX }, [-800, -515, -231, 54, 908, 1193, 1477])
        XCTAssertEqual(seven.map { $0.width }, [283, 282, 283, 852, 283, 282, 283])
        XCTAssertEqual(seven.map { $0.minY }, Array(repeating: -720, count: 7))
        XCTAssertEqual(seven.map { $0.height }, Array(repeating: 720, count: 7))
        XCTAssertEqual(seven.last?.maxX, odyssey.maxX, "правый край — встык")

        // Чётное число: слева меньшая половина, главный — на месте floor((n−1)/2).
        let six = ArrangeLayout.frames(count: 6, in: odyssey, mode: .center, minCellWidth: 220, gap: 2)
        XCTAssertEqual(six.count, 6)
        XCTAssertEqual(six[2], seven[3], "главный — та же средняя треть")
        XCTAssertEqual(six.filter { $0.maxX <= seven[3].minX }.count, 2)
        XCTAssertEqual(six.filter { $0.minX >= seven[3].maxX }.count, 3)
        // Одно окно — только средняя треть.
        XCTAssertEqual(ArrangeLayout.frames(count: 1, in: odyssey, mode: .center, gap: 2), [seven[3]])

        // too-small считается по числу окон: 7 окон по 282 влезают при 220 и 280, 9 окон — нет.
        XCTAssertTrue(ArrangeLayout.centerFits(count: 7, in: odyssey, minCellWidth: 280, gap: 2))
        XCTAssertFalse(ArrangeLayout.centerFits(count: 9, in: odyssey, minCellWidth: 280, gap: 2))
        XCTAssertTrue(ArrangeLayout.centerFits(count: 9, in: odyssey, minCellWidth: 200, gap: 2))

    }

    /// Раскладки «4», «5» и «5×2» (план WF21): сетка задана, рамок ровно столько, сколько
    /// в ней мест, — лишним окнам их не достаётся, и трогать эти окна некому.
    func testArrangeModesGiveFixedGrids() {
        let area = CGRect(x: 0, y: 34, width: 1470, height: 860) // 15" Элвиса
        XCTAssertEqual(ArrangeLayout.Mode.allCases.map { $0.rawValue }, ["row", "4", "5", "5x2", "center"])
        XCTAssertNil(ArrangeLayout.capacity(of: .ribbon), "лента берёт все окна")
        let fixed: [ArrangeLayout.Mode] = [.four, .five, .tenGrid]
        XCTAssertEqual(fixed.map { ArrangeLayout.capacity(of: $0) }, [4, 5, 10])

        // «5 в ряд»: пять столбцов во всю высоту, шестому окну рамки нет.
        let five = ArrangeLayout.frames(count: 6, in: area, mode: .five)
        XCTAssertEqual(five.count, 5)
        XCTAssertEqual(five[0], CGRect(x: 0, y: 34, width: 294, height: 860))
        XCTAssertEqual(five[4].maxX, area.maxX)
        // Окон меньше, чем ячеек, — сетка остаётся, окна не растягиваем.
        XCTAssertEqual(ArrangeLayout.frames(count: 2, in: area, mode: .four).map { $0.width },
                       [368, 367])

        // «5×2»: слева направо, сверху вниз; ряд — вполовину высоты, одиннадцатому места нет.
        let grid = ArrangeLayout.frames(count: 6, in: area, mode: .tenGrid)
        XCTAssertEqual(grid[0], CGRect(x: 0, y: 34, width: 294, height: 430))
        XCTAssertEqual(grid[5], CGRect(x: 0, y: 464, width: 294, height: 430))
        XCTAssertEqual(ArrangeLayout.frames(count: 12, in: area, mode: .tenGrid).count, 10)
        // Лента считает столбцы сама и рамку даёт каждому окну — счёт прежний.
        XCTAssertEqual(ArrangeLayout.frames(count: 6, in: area, minCellWidth: 280).count, 6)

        // Влезает ли раскладка: у Элвиса minWindowWidth 280 — пятёрка встаёт по 294; у команды
        // 360 — пятёрка уже серая, а четвёрка (367) ещё нет. Лента влезает всегда.
        XCTAssertTrue(ArrangeLayout.fits(.five, in: area, minCellWidth: 280))
        XCTAssertTrue(ArrangeLayout.fits(.tenGrid, in: area, minCellWidth: 280))
        XCTAssertFalse(ArrangeLayout.fits(.five, in: area, minCellWidth: 360))
        XCTAssertTrue(ArrangeLayout.fits(.four, in: area, minCellWidth: 360))
        XCTAssertTrue(ArrangeLayout.fits(.ribbon, in: area, minCellWidth: 999))

        // Последняя раскладка живёт в настройках приложения; чужое слово в них — лента.
        let store = ThemeStore(defaults: MemoryThemeDefaults())
        XCTAssertEqual(store.arrangeMode, .ribbon)
        store.arrangeMode = .tenGrid
        XCTAssertEqual(store.arrangeMode, .tenGrid)
        let junk = MemoryThemeDefaults()
        junk.values[ThemeStore.arrangeModeKey] = "5x3"
        XCTAssertEqual(ThemeStore(defaults: junk).arrangeMode, .ribbon)
    }

    /// Имя раскладки приложение предлагает само (#5769): проекты окон слева направо.
    func testSuggestedLayoutNameListsProjects() {
        func window(_ id: CGWindowID, _ folder: String, x: CGFloat) -> PimpWindow {
            PimpWindow(id: id, title: "Окно \(id)", chat: "local_\(id)", folder: folder,
                       frame: CGRect(x: x, y: 34, width: 290, height: 859))
        }
        let pimp = "/Users/dev/Projects/PimpMyClaude"
        let vkus = "/Users/dev/Projects/VkusnoffKz"
        let dict = "/Users/dev/Projects/Dictatorik"
        let skil = "/Users/dev/Projects/SkilZZZ"

        XCTAssertEqual(LayoutsStore.suggestedName(for: []), "")
        XCTAssertEqual(LayoutsStore.suggestedName(for: [window(1, pimp, x: 0)]), "PimpMyClaude")
        // Порядок — по левому краю рамки, а не по порядку в списке (он идёт по слоям окон).
        XCTAssertEqual(LayoutsStore.suggestedName(for: [window(1, vkus, x: 300),
                                                        window(2, pimp, x: 0)]),
                       "PimpMyClaude и VkusnoffKz")
        XCTAssertEqual(LayoutsStore.suggestedName(for: [window(1, pimp, x: 0),
                                                        window(2, vkus, x: 300),
                                                        window(3, dict, x: 600)]),
                       "PimpMyClaude, VkusnoffKz и Dictatorik")
        // Больше трёх — две папки и счёт остальных.
        XCTAssertEqual(LayoutsStore.suggestedName(for: [window(1, pimp, x: 0),
                                                        window(2, vkus, x: 300),
                                                        window(3, dict, x: 600),
                                                        window(4, skil, x: 900)]),
                       "PimpMyClaude, VkusnoffKz и ещё 2")
        // Повторы и окна без папки в имя не идут; папок не осталось вовсе — имени нет.
        XCTAssertEqual(LayoutsStore.suggestedName(for: [window(1, pimp, x: 0),
                                                        window(2, pimp, x: 300),
                                                        window(3, "", x: 600)]),
                       "PimpMyClaude")
        XCTAssertEqual(LayoutsStore.suggestedName(for: [window(1, "", x: 0)]), "")
        // Три длинных имени в потолок не влезают — то же «и ещё N», и оно короче потолка.
        let long = String(repeating: "Проект", count: 5)
        let name = LayoutsStore.suggestedName(for: [window(1, "/tmp/\(long)1", x: 0),
                                                    window(2, "/tmp/\(long)2", x: 300),
                                                    window(3, "/tmp/\(long)3", x: 600)])
        XCTAssertEqual(name, "\(long)1, \(long)2 и ещё 1")
        XCTAssertLessThanOrEqual(name.count, LayoutsStore.nameLimit)
    }

    /// Раскладка для меню: два места по сетке «5 в ряд».
    private static func layout(_ name: String) -> WindowLayout {
        WindowLayout(name: name, at: PimpChannel.date("2026-09-08T03:00:00Z")!, mode: .five,
                     cells: [LayoutCell(folder: "/tmp/Pimp", chat: "main", title: "Claude", cell: 0),
                             LayoutCell(folder: "/tmp/Vkus", chat: "local_1", title: "Вкуснофф",
                                        cell: 1)])
    }

    func testOrderKeepsRowsLeftToRight() {
        let frames = [
            CGRect(x: 800, y: 0, width: 400, height: 400),   // 0 — правое верхнее
            CGRect(x: 0, y: 40, width: 400, height: 400),    // 1 — левое верхнее (тот же ряд, Δy < 60)
            CGRect(x: 0, y: 500, width: 400, height: 400),   // 2 — нижнее
        ]
        XCTAssertEqual(ArrangeLayout.order(of: frames), [1, 0, 2])
    }

    /// Плитка, которая на ЭТОМ экране не влезает, гаснет (#5733), а с WF77 «влезает»
    /// считает и зазор (критик п. 11): без него ячейка плитки и живая ячейка расходились
    /// ровно на `gap`, и плитка на грани начинала врать. ⌥⌘A и «▦ Расставить» сюда больше
    /// не заходят вовсе — они идут умным путём, которому экран мал не бывает.
    func testLayoutFitsCountsTheGap() {
        // Экран Элвиса при минимуме окна 360 пятёрку уже не держит, а четвёрку — да.
        let laptop = CGRect(x: 0, y: 34, width: 1470, height: 860)
        XCTAssertFalse(ArrangeLayout.fits(.five, in: laptop, minCellWidth: 360))
        XCTAssertTrue(ArrangeLayout.fits(.ribbon, in: laptop, minCellWidth: 360))
        // Зазор 40: пятёрка по 294 при минимуме 280 влезала, а с зазором ячейка 262 — нет.
        XCTAssertTrue(ArrangeLayout.fits(.five, in: laptop, minCellWidth: 280))
        XCTAssertFalse(ArrangeLayout.fits(.five, in: laptop, minCellWidth: 280, gap: 40))
        XCTAssertTrue(ArrangeLayout.fits(.four, in: laptop, minCellWidth: 280, gap: 40))
        // Умолчание — прежний ответ побайтно: зазора у старых вызовов нет.
        XCTAssertEqual(ArrangeLayout.fits(.five, in: laptop, minCellWidth: 280),
                       ArrangeLayout.fits(.five, in: laptop, minCellWidth: 280, gap: 0))
    }

    // MARK: - умная расстановка (план WF77)

    /// Числа Элвиса 20.09: Odyssey над макбуком, рабочая область x −796…2212, y −846…0.
    private static let odyssey = CGRect(x: -796, y: -846, width: 3008, height: 846)
    /// Макбук под ним: рабочая 1205×802.
    private static let macbook = CGRect(x: 0, y: 30, width: 1205, height: 802)
    private static let minCell: CGFloat = 280
    private static let gap: CGFloat = 5

    /// Потолок столбцов (WF94, #7730: девять — было шесть, слово Элвиса 20.09; макбуковский —
    /// четыре) и потолок рядов. Зазор в потолке обязателен (критик блокер 7): при gap 40
    /// четвёртый столбец макбука дал бы 261 pt.
    func testColumnCapFollowsScreenAndGap() {
        let odyssey = ClaudeAXTests.odyssey, macbook = ClaudeAXTests.macbook
        XCTAssertEqual(ArrangeLayout.cap(width: odyssey.width, minCellWidth: 280, gap: 5), 9)
        // Потолок держит девять и там, где по ширине влезло бы десять и больше.
        XCTAssertEqual(ArrangeLayout.cap(width: 2560, minCellWidth: 220, gap: 5), 9)
        XCTAssertEqual(ArrangeLayout.cap(width: macbook.width, minCellWidth: 280, gap: 5), 4)
        XCTAssertEqual(ArrangeLayout.cap(width: macbook.width, minCellWidth: 280, gap: 40), 3)
        // Экран уже одного окна — один столбец, а не ноль.
        XCTAssertEqual(ArrangeLayout.cap(width: 200, minCellWidth: 280, gap: 5), 1)
        XCTAssertEqual(ArrangeLayout.cap(width: 0, minCellWidth: 280, gap: 5), 1)
        // Рядов столько, сколько держит высота при `minCellHeight` 360.
        XCTAssertEqual(ArrangeLayout.capRows(height: odyssey.height, gap: 5), 2)
        XCTAssertEqual(ArrangeLayout.capRows(height: macbook.height, gap: 5), 2)
        XCTAssertEqual(ArrangeLayout.capRows(height: 400, gap: 5), 1)
    }

    /// Зазор живёт ТОЛЬКО между окнами: у краёв рабочей области, сверху и снизу окна
    /// прижаты встык (слова Элвиса 20.09 после критика). Умолчание 0 оставляет прежние
    /// рамки побайтно — старые эталоны и раскладки не едут.
    func testGapLivesBetweenWindowsOnly() {
        let area = ClaudeAXTests.odyssey
        let cells = ArrangeLayout.cells(cols: 6, rows: 1, count: 6, in: area, gap: 5)
        XCTAssertEqual(cells.first?.minX, area.minX, "левый край — встык")
        XCTAssertEqual(cells.last?.maxX, area.maxX, "правый край — встык")
        XCTAssertEqual(cells.map { $0.minY }, Array(repeating: area.minY, count: 6))
        XCTAssertEqual(cells.map { $0.height }, Array(repeating: area.height, count: 6))
        for i in 1..<cells.count {
            XCTAssertEqual(cells[i].minX - cells[i - 1].maxX, 5, "зазор между \(i - 1) и \(i)")
        }
        // Ряды — так же по высоте.
        let rows = ArrangeLayout.cells(cols: 4, rows: 2, count: 8, in: area, gap: 5)
        XCTAssertEqual(rows[0].minY, area.minY)
        XCTAssertEqual(rows[4].minY - rows[0].maxY, 5)
        XCTAssertEqual(rows[7].maxY, area.maxY)

        // Зазора нет — рамки те же, что были до WF77 (побайтно).
        for count in [1, 2, 3, 5, 6, 12] {
            for mode in ArrangeLayout.Mode.allCases {
                XCTAssertEqual(ArrangeLayout.frames(count: count, in: area, mode: mode,
                                                    minCellWidth: 280, gap: 0),
                               ArrangeLayout.frames(count: count, in: area, mode: mode,
                                                    minCellWidth: 280),
                               "\(mode.rawValue) на \(count) окнах")
            }
        }
    }

    /// Три окна Элвиса стоят в третях Odyssey — «расставить» не двигает НИКОГО (слово Элвиса
    /// 20.09: «окна, которые уже стояли на месте, никуда не переводить»). С WF105 (#8071) «сидит»
    /// держит окно только в сетке `least` — три окна, три столбца на всю ширину.
    func testSmartKeepsWindowsThatAlreadySit() {
        let area = ClaudeAXTests.odyssey
        let thirds = ArrangeLayout.cells(cols: 3, rows: 1, count: 3, in: area, gap: 5)
        XCTAssertEqual(thirds.map { $0.minX }, [-796, 208, 1213])
        XCTAssertEqual(thirds.map { $0.width }, [999, 1000, 999])

        // Стоят «наоборот» — порядок сидящих не трогаем.
        let standing = [thirds[1], thirds[0], thirds[2]]
        XCTAssertEqual(ArrangeLayout.smart(frames: standing, in: area,
                                           minCellWidth: ClaudeAXTests.minCell, gap: 5),
                       standing, "сидящие окна не двигаются вовсе")
        // Живые рамки сходятся с ячейками не точка в точку — допуск 8 pt узнаёт в них ту же
        // сетку (место не меняется), а рамка доводится до точной ячейки: «не совсем ровно
        // стоят — ты должен это без моих слов делать».
        let live = [CGRect(x: -792, y: -842, width: 995, height: 838),
                    CGRect(x: 210, y: -842, width: 997, height: 838),
                    CGRect(x: 1216, y: -842, width: 995, height: 838)]
        XCTAssertEqual(ArrangeLayout.smart(frames: live, in: area,
                                           minCellWidth: ClaudeAXTests.minCell, gap: 5), thirds)
        // Окна встык без зазора (живой случай 21.09) — те же места, но с зазором.
        let tight = ArrangeLayout.cells(cols: 3, rows: 1, count: 3, in: area, gap: 0)
        XCTAssertEqual(ArrangeLayout.smart(frames: tight, in: area,
                                           minCellWidth: ClaudeAXTests.minCell, gap: 5), thirds)
        // Трое в шестых долях (сетка шире нужной) — больше не держат сетку: три трети (#8071).
        let sixths = ArrangeLayout.cells(cols: 6, rows: 1, count: 6, in: area, gap: 5)
        XCTAssertEqual(ArrangeLayout.smart(frames: Array(sixths[0..<3]), in: area,
                                           minCellWidth: ClaudeAXTests.minCell, gap: 5), thirds)
    }

    /// К трём стоящим окнам добавилось четвёртое «где попало»: трое стоят в четвертях, новое
    /// встаёт в свободную ячейку (слово Элвиса: «есть свободное место и одно-два окна
    /// болтаются неприкаянно — заполни ими свободное место»).
    func testSmartSeatsStrayWindowIntoFreeCell() {
        let area = ClaudeAXTests.odyssey
        let quarters = ArrangeLayout.cells(cols: 4, rows: 1, count: 4, in: area, gap: 5)
        let frames = Array(quarters[0..<3]) + [CGRect(x: 900, y: -500, width: 820, height: 600)]
        let placed = ArrangeLayout.smart(frames: frames, in: area,
                                         minCellWidth: ClaudeAXTests.minCell, gap: 5)
        XCTAssertEqual(Array(placed[0..<3]), Array(quarters[0..<3]), "трое стоят")
        XCTAssertEqual(placed[3], quarters[3])
    }

    /// Никто не сидит — окна делят экран поровну: три окна «как попало» становятся тремя
    /// столбцами во всю ширину и высоту (ничья кандидатов — наименьшее число столбцов).
    func testSmartSpreadsStrayWindowsEvenly() {
        let area = ClaudeAXTests.odyssey
        let frames = [CGRect(x: 40, y: -700, width: 900, height: 500),
                      CGRect(x: -700, y: -800, width: 600, height: 700),
                      CGRect(x: 1500, y: -400, width: 700, height: 300)]
        let placed = ArrangeLayout.smart(frames: frames, in: area,
                                         minCellWidth: ClaudeAXTests.minCell, gap: 5)
        // Порядок неприкаянных — по их собственным рамкам, слева направо.
        XCTAssertEqual(placed.map { $0.minX }, [208, -796, 1213])
        XCTAssertEqual(placed.map { $0.width }, [1000, 999, 999])
        XCTAssertEqual(placed.map { $0.minY }, Array(repeating: area.minY, count: 3))
        XCTAssertEqual(placed.map { $0.height }, Array(repeating: area.height, count: 3))
    }

    /// Дырок посередине не оставляем (критик зам. 6): сидят две правые четверти, два окна
    /// неприкаянные — они встают в свободные ячейки той же сетки слева.
    func testSmartFillsCellsNextToSeatedOnes() {
        let area = ClaudeAXTests.odyssey
        let quarters = ArrangeLayout.cells(cols: 4, rows: 1, count: 4, in: area, gap: 5)
        let frames = [quarters[2], quarters[3],
                      CGRect(x: -700, y: -600, width: 400, height: 300),
                      CGRect(x: 100, y: -300, width: 500, height: 200)]
        let placed = ArrangeLayout.smart(frames: frames, in: area,
                                         minCellWidth: ClaudeAXTests.minCell, gap: 5)
        XCTAssertEqual(Array(placed[0..<2]), [quarters[2], quarters[3]], "сидящие стоят")
        XCTAssertEqual(Array(placed[2..<4]), [quarters[0], quarters[1]])
        // Сами ячейки: выбор свободных считается и отдельно от рамок.
        XCTAssertEqual(ArrangeLayout.freeCells(count: 4, cells: 6, taken: [4, 5]), [2, 3])
        XCTAssertEqual(ArrangeLayout.freeCells(count: 4, cells: 6, taken: []), [0, 1, 2, 3, 4, 5])
        // Занятые разошлись шире отрезка — берём просто самые левые свободные.
        XCTAssertEqual(ArrangeLayout.freeCells(count: 3, cells: 6, taken: [0, 5]), [1, 2, 3, 4])
    }

    /// Двенадцать окон на прежнем Odyssey 846 pt (экран держит два ряда) — два ряда (потолок
    /// девять столбцов, WF94), а не двенадцать столбиков: при ничьей берётся наименьшее число
    /// столбцов, `ceil(12/2) = 6`. Семь окон с WF94 встают в один ряд.
    func testSmartAddsSecondRowWhenWindowsDoNotFitOneRow() {
        let area = ClaudeAXTests.odyssey
        let frames = (0..<12).map { i in
            CGRect(x: CGFloat(i) * 130 - 700, y: -700 + CGFloat(i) * 10, width: 600, height: 400)
        }
        let placed = ArrangeLayout.smart(frames: frames, in: area,
                                         minCellWidth: ClaudeAXTests.minCell, gap: 5)
        XCTAssertEqual(Set(placed.map { $0.minY }).count, 2, "ровно два ряда")
        XCTAssertEqual(Set(placed.map { $0.minX }).count, 6, "шесть столбцов")
        XCTAssertEqual(placed.map { $0.height }, Array(repeating: 421, count: 6) + Array(repeating: 420, count: 6))
        let seven = ArrangeLayout.smart(frames: Array(frames[0..<7]), in: area,
                                        minCellWidth: ClaudeAXTests.minCell, gap: 5)
        XCTAssertEqual(Set(seven.map { $0.minY }).count, 1, "семь окон — один ряд")
        XCTAssertEqual(seven.map { $0.height }, Array(repeating: area.height, count: 7))
        XCTAssertEqual(placed.first?.minY, area.minY)
        XCTAssertEqual(placed.last?.maxY, area.maxY)
    }

    /// Окон больше, чем мест на экране, — лишние не трогаем вовсе (слово Элвиса 08.09).
    /// Макбук: четыре столбца × два ряда = восемь мест, девятое окно остаётся где стояло.
    /// Экран в два ряда половинок не знает (WF94: они только у экрана в один ряд и от 10 окон).
    func testSmartLeavesWindowsBeyondCapacityAlone() {
        let area = ClaudeAXTests.macbook
        let stray = CGRect(x: 60, y: 300, width: 700, height: 420)
        let frames = (0..<8).map { i in
            CGRect(x: CGFloat(i % 4) * 120, y: 40 + CGFloat(i / 4) * 90, width: 640, height: 380)
        } + [stray]
        let placed = ArrangeLayout.smart(frames: frames, in: area,
                                         minCellWidth: ClaudeAXTests.minCell, gap: 5)
        XCTAssertEqual(placed[8], stray, "девятому окна места нет — его не двигают")
        XCTAssertEqual(Set(placed[0..<8].map { $0.minX }).count, 4)
        XCTAssertEqual(Set(placed[0..<8].map { $0.minY }).count, 2)
        XCTAssertEqual(placed[0], CGRect(x: 0, y: 30, width: 298, height: 399))
    }

    /// Окна с разных экранов остаются каждое на своём (решение 2 плана): экран выбирается
    /// по ЦЕНТРУ рамки в ПОЛНОЙ рамке экрана, а сетка считается по рабочей области.
    func testSmartKeepsWindowsOnTheirOwnScreens() {
        let odyssey = ClaudeAXTests.odyssey, macbook = ClaudeAXTests.macbook
        let screens = [(full: CGRect(x: 0, y: 0, width: 1280, height: 832), usable: macbook),
                       (full: odyssey, usable: odyssey)]
        let onMac = CGRect(x: 300, y: 200, width: 600, height: 500)
        let onBig = [CGRect(x: -700, y: -800, width: 900, height: 700),
                     CGRect(x: 1400, y: -600, width: 800, height: 500)]
        XCTAssertEqual(Screens.assign(screens: screens.map { $0.full },
                                      frames: [onMac] + onBig), [0, 1, 1])
        let placed = ArrangeLayout.smart(frames: [onMac] + onBig, screens: screens,
                                         minCellWidth: ClaudeAXTests.minCell, gap: 5)
        XCTAssertEqual(placed[0], macbook, "одно окно на макбуке — во весь его экран")
        XCTAssertEqual(placed[1].minX, odyssey.minX)
        XCTAssertEqual(placed[2].maxX, odyssey.maxX)
        XCTAssertEqual(placed[1].width + placed[2].width + 5, odyssey.width)
        // Центр рамки нигде — экран с меню-баром (первый), окно с него не уезжает.
        XCTAssertEqual(Screens.assign(screens: screens.map { $0.full },
                                      frames: [CGRect(x: 9000, y: 9000, width: 10, height: 10)]),
                       [0])
    }

    /// Навязанный порядок ради нового окна касается только ЕГО экрана (проверка WF77,
    /// блокер 2): на другом мониторе окна, сидящие в правых ячейках, остаются где сидят.
    func testSmartImposedOrderStaysOnAnchorScreen() {
        let odyssey = ClaudeAXTests.odyssey, macbook = ClaudeAXTests.macbook
        let screens = [(full: CGRect(x: 0, y: 0, width: 1280, height: 832), usable: macbook),
                       (full: odyssey, usable: odyssey)]
        let sixths = ArrangeLayout.cells(cols: 6, rows: 1, count: 6, in: odyssey, gap: 5)
        let halves = ArrangeLayout.cells(cols: 2, rows: 1, count: 2, in: macbook, gap: 5)
        // На Odyssey сидят ячейки 4 и 5; на макбуке окно и новое (якорь, индекс 3) поверх.
        let fresh = CGRect(x: 40, y: 70, width: 600, height: 500)
        let frames = [sixths[4], sixths[5], halves[0], fresh]
        let placed = ArrangeLayout.smart(frames: frames, screens: screens,
                                         minCellWidth: ClaudeAXTests.minCell, gap: 5,
                                         order: [3, 0, 1, 2], anchor: 3)
        XCTAssertEqual(placed[0], sixths[4], "чужой экран не перекладывается")
        XCTAssertEqual(placed[1], sixths[5])
        XCTAssertEqual(placed[3], halves[0], "новое окно — первым на своём экране")
        XCTAssertEqual(placed[2], halves[1])
    }

    /// Порог «сидящих не меньше половины» (КП-6 критика): одно случайно совпавшее окно
    /// сетку из шести столбцов не диктует — четыре окна делят экран поровну.
    func testSmartIgnoresSingleAccidentalMatch() {
        let area = ClaudeAXTests.odyssey
        let sixths = ArrangeLayout.cells(cols: 6, rows: 1, count: 6, in: area, gap: 5)
        let frames = [sixths[2],
                      CGRect(x: -700, y: -600, width: 400, height: 300),
                      CGRect(x: 100, y: -300, width: 500, height: 200),
                      CGRect(x: 1500, y: -700, width: 600, height: 400)]
        let placed = ArrangeLayout.smart(frames: frames, in: area,
                                         minCellWidth: ClaudeAXTests.minCell, gap: 5)
        XCTAssertEqual(Set(placed.map { $0.minX }).count, 4, "четыре равных столбца")
        XCTAssertNotEqual(placed[0], sixths[2], "случайно совпавшее окно тоже переехало")
        XCTAssertEqual(placed.map { $0.height }, Array(repeating: area.height, count: 4))
    }

    /// Порядок НАВЯЗАН (новое окно «слева» и «посередине»): сетка та же, но окна кладутся
    /// подряд — «сидит» там уже никого не держит.
    func testSmartFollowsGivenOrder() {
        let area = ClaudeAXTests.odyssey
        let thirds = ArrangeLayout.cells(cols: 3, rows: 1, count: 3, in: area, gap: 5)
        let frames = [thirds[0], thirds[1], CGRect(x: 900, y: -500, width: 820, height: 600)]
        let placed = ArrangeLayout.smart(frames: frames, in: area,
                                         minCellWidth: ClaudeAXTests.minCell, gap: 5,
                                         order: [2, 0, 1])
        XCTAssertEqual(placed, [thirds[1], thirds[2], thirds[0]])
        // Окно, которого в порядке не назвали, встаёт за названными — по своему месту.
        XCTAssertEqual(ArrangeLayout.smart(frames: frames, in: area,
                                           minCellWidth: ClaudeAXTests.minCell, gap: 5,
                                           order: [2]),
                       [thirds[1], thirds[2], thirds[0]])
    }

    /// «Посередине» у сетки с рядами — середина ПЕРВОГО ряда, а не всего порядка (#5560):
    /// в «5×2» с девятью окнами середина всего порядка давала место 5, то есть начало
    /// нижнего ряда, — а Элвис просил середину.
    func testInsertIndexTakesMiddleOfFirstRow() {
        // Лента рядов не задаёт — счёт прежний, как в WF36.
        XCTAssertEqual(ArrangeLayout.insertIndex(of: .middle, count: 9), 5)
        XCTAssertNil(ArrangeLayout.grid(of: .ribbon)?.cols)
        // «5×2»: в первом ряду пять мест, середина — третье.
        let cols = ArrangeLayout.grid(of: .tenGrid)?.cols
        XCTAssertEqual(cols, 5)
        XCTAssertEqual(ArrangeLayout.insertIndex(of: .middle, count: 9, columns: cols), 2)
        // Окон меньше, чем мест в ряду, — считаем по окнам, как раньше.
        XCTAssertEqual(ArrangeLayout.insertIndex(of: .middle, count: 2, columns: cols), 1)
        XCTAssertEqual(ArrangeLayout.insertIndex(of: .middle, count: 3, columns: 4), 2)
        // Края не двигаются: слева — первым, справа — последним во всём порядке.
        XCTAssertEqual(ArrangeLayout.insertIndex(of: .left, count: 9, columns: cols), 0)
        XCTAssertEqual(ArrangeLayout.insertIndex(of: .right, count: 9, columns: cols), 9)
        // Мусорное число столбцов счёт не роняет.
        XCTAssertEqual(ArrangeLayout.insertIndex(of: .middle, count: 4, columns: 0), 2)
    }

    /// Повторы `setFrame` больше не спят на главной нити (#5557): сон стоял в цикле по окнам
    /// и умножался на их число — до 2,5 с замершего меню-бара на пяти окнах, а через тот же
    /// `setFrame` ходят «Расставить», канал «Пимп» и возврат раскладок.
    ///
    /// С WF77 повторяем и промах РАЗМЕРА (находка живьём 20.09: за один заход «позиция →
    /// размер → позиция» размер не берётся вовсе — окно остаётся прежней ширины и высоты,
    /// и «расставило как попало» было ровно этим). Кроме ширины уже `minWidth`: её Electron
    /// зажимает осознанно, и весь бюджет повторов уходил туда впустую (#5733).
    func testSetFrameRetriesWithoutSleepingOnMainThread() {
        let want = CGRect(x: 100, y: 100, width: 800, height: 600)
        // Позиция не встала — окно ещё едет, повтор нужен (грабли гейта WF36).
        XCTAssertTrue(ClaudeActions.needsFrameRetry(now: CGRect(x: 140, y: 100, width: 800, height: 600),
                                                    want: want))
        // Позиция встала, а размер остался прежним — повтор нужен (WF77): второй круг
        // пишет размер уже после того, как встал верх окна, и высота наконец берётся.
        XCTAssertTrue(ClaudeActions.needsFrameRetry(now: CGRect(x: 100, y: 100, width: 1200, height: 900),
                                                    want: want))
        XCTAssertTrue(ClaudeActions.needsFrameRetry(now: CGRect(x: 100, y: 100, width: 800, height: 838),
                                                    want: want))
        // Ячейка уже минимальной ширины окна — ширину Electron не отдаст, и это не повод
        // для повтора: позиция и высота на месте.
        let narrow = CGRect(x: 100, y: 100, width: 241, height: 600)
        XCTAssertFalse(ClaudeActions.needsFrameRetry(now: CGRect(x: 100, y: 100, width: 280, height: 600),
                                                     want: narrow, minWidth: 280))
        XCTAssertTrue(ClaudeActions.needsFrameRetry(now: CGRect(x: 100, y: 100, width: 280, height: 600),
                                                    want: narrow, minWidth: 240),
                      "минимум ниже заказа — ширину спрашиваем снова")
        // Допуск тот же, что у `frameMatches`.
        XCTAssertFalse(ClaudeActions.needsFrameRetry(now: CGRect(x: 102, y: 98, width: 802, height: 598),
                                                     want: want))
        // Рамки нет вовсе (окно закрылось) — повторять некому.
        XCTAssertFalse(ClaudeActions.needsFrameRetry(now: nil, want: want))
        // Кругов четыре: «позиция → пауза → размер» на этом Маке требует второго захода.
        XCTAssertEqual(ClaudeActions.frameRetries, 4)

        // Вызов на окне, которого нет: AX молчит, и мы возвращаемся сразу — до WF43 здесь
        // сгорали два `Thread.sleep` по 0,25 с прямо в главной нити. Минимум ширины
        // подставляем свой: живой claude.json в прогоне не читаем.
        var scheduled: [TimeInterval] = []
        let live = ClaudeActions.frameSchedule
        let liveMin = ClaudeActions.minFrameWidth
        ClaudeActions.frameSchedule = { delay, _ in scheduled.append(delay) }
        ClaudeActions.minFrameWidth = { 280 }
        defer {
            ClaudeActions.frameSchedule = live
            ClaudeActions.minFrameWidth = liveMin
        }
        let started = Date()
        XCTAssertFalse(ClaudeActions.setFrame(AXUIElementCreateApplication(999_999), want))
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.1, "повторы всё ещё спят на нити")
        XCTAssertTrue(scheduled.isEmpty, "мёртвому окну повтор не назначаем")
        XCTAssertEqual(ClaudeActions.frameRetryPause, 0.25)
    }

    /// Урок ElvisOS (#5791, пункт «а»): СВЕЖЕМУ окну рамка ставится «размер → позиция →
    /// размер». Система урезает запомненную с прошлого раза высоту по нижнему краю экрана
    /// (под Dock), а повторный размер после позиции глотает — нижний ряд стабильно получал
    /// 488 точек вместо 434. Окну, которое уже стоит на экране, порядок прежний: последним
    /// словом обязана быть позиция, иначе смена размера у правого края снова его сдвинет.
    func testFreshWindowGetsSizeBeforePosition() {
        let want = CGRect(x: 100, y: 500, width: 700, height: 434)
        XCTAssertEqual(ClaudeActions.frameSteps(want, fresh: true),
                       [.size(want.size), .position(want.origin), .size(want.size)])
        XCTAssertEqual(ClaudeActions.frameSteps(want, fresh: false),
                       [.position(want.origin), .size(want.size), .position(want.origin)])
        // Порядок по умолчанию — прежний: «Расставить» и канал «Пимп» ничего не заметили.
        XCTAssertEqual(ClaudeActions.frameSteps(want, fresh: false), {
            var steps: [ClaudeActions.FrameStep] = []
            steps.append(.position(want.origin))
            steps.append(.size(want.size))
            steps.append(.position(want.origin))
            return steps
        }())
        // Повтор идёт тем же порядком: `fresh` доезжает до следующего захода.
        var scheduled = 0
        let live = ClaudeActions.frameSchedule
        let liveMin = ClaudeActions.minFrameWidth
        ClaudeActions.frameSchedule = { _, _ in scheduled += 1 }
        ClaudeActions.minFrameWidth = { 280 }
        defer {
            ClaudeActions.frameSchedule = live
            ClaudeActions.minFrameWidth = liveMin
        }
        XCTAssertFalse(ClaudeActions.setFrame(AXUIElementCreateApplication(999_999), want,
                                              fresh: true))
        XCTAssertEqual(scheduled, 0, "мёртвому окну повтор не назначаем")
    }

    /// Урок ElvisOS (#5791, пункт «в»): у каждого экземпляра Claude в выдаче оконного сервера
    /// лежит пара безымянных служебных окон 800×600 по координатам 335,164 — по размеру их от
    /// чата не отличить, а имя сервер отдаёт только при разрешении «Запись экрана». Плюс
    /// прозрачные и мелочь меньше 200×150: прежний порог 120×120 пускал их все, а «Обкэшить»
    /// отдаёт рамку донора ПЕРВОМУ незнакомому окну и потом закрывает донора.
    func testServiceWindowsAreNotTakenForChats() {
        XCTAssertTrue(ClaudeApp.isServiceWindow(frame: CGRect(x: 335, y: 164, width: 800, height: 600),
                                                alpha: 1))
        XCTAssertTrue(ClaudeApp.isServiceWindow(frame: CGRect(x: 100, y: 100, width: 700, height: 500),
                                                alpha: 0))
        XCTAssertTrue(ClaudeApp.isServiceWindow(frame: CGRect(x: 100, y: 100, width: 180, height: 500),
                                                alpha: 1), "мелочь по ширине")
        XCTAssertTrue(ClaudeApp.isServiceWindow(frame: CGRect(x: 100, y: 100, width: 700, height: 140),
                                                alpha: 1), "мелочь по высоте")
        // Настоящее окно чата ровно того же размера, но в другом месте экрана — трогать нельзя.
        XCTAssertFalse(ClaudeApp.isServiceWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                                                 alpha: 1))
        XCTAssertFalse(ClaudeApp.isServiceWindow(frame: CGRect(x: 335, y: 164, width: 294, height: 900),
                                                 alpha: 1), "узкая ячейка раскладки — это чат")
        // Порог прозрачности — граница, а не «почти ноль»: окно чата с лёгкой прозрачностью
        // окном чата и остаётся.
        XCTAssertTrue(ClaudeApp.isServiceWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                                                alpha: 0.04))
        XCTAssertFalse(ClaudeApp.isServiceWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                                                 alpha: 0.05))
        XCTAssertEqual(ClaudeApp.serviceWindowFrame, CGRect(x: 335, y: 164, width: 800, height: 600))
        XCTAssertEqual(ClaudeApp.minWindowSize, CGSize(width: 200, height: 150))
        XCTAssertEqual(ClaudeApp.minWindowAlpha, 0.05)
    }

    /// Урок ElvisOS (#5791, пункт «б»): `kAXRaiseAction` поднимает окно только среди окон
    /// своего приложения — пока Claude не активирован, его окна остаются под чужими
    /// («нажимаю, появляется одно окно, надо жать раза три»). Значит активация ПЕРВОЙ.
    /// И одного подъёма мало внутри самого Claude: без `kAXMain` и `kAXFocused` Electron
    /// возвращает вперёд своё прежнее ключевое окно.
    func testFocusActivatesBeforeRaising() {
        let steps = ClaudeApp.focusSteps
        XCTAssertEqual(steps.first, .activate, "подъём до активации не поднимает над чужими")
        let raise = try? XCTUnwrap(steps.firstIndex(of: .raise))
        let activate = try? XCTUnwrap(steps.firstIndex(of: .activate))
        XCTAssertNotNil(raise)
        XCTAssertNotNil(activate)
        if let raise = raise, let activate = activate { XCTAssertLessThan(activate, raise) }
        XCTAssertTrue(steps.contains(.main))
        XCTAssertTrue(steps.contains(.focused))
    }

    // MARK: - клавиши

    /// Клавиши PMP в Claude (WF237: меню жёлтой кнопки снято, клавиши остались — лист 48, «Решено»).
    func testHotkeysMatchReadme() {
        let expected: [(ClaudeCommand, String, UInt32, KeyMods, Bool)] = [
            (.cashout, "Обкэшить", 0x2D, [.command, .shift], true),
            // ⌘N — штатная клавиша Claude: не регистрируем.
            (.newChat, "Новый чат", 0x2D, [.command], false),
            (.newWindow, "Новое окно", 0x2D, [.command, .option], true),
            (.collapse, "Свернуть", 0x7D, [.command, .option], true),
            (.expand, "Развернуть", 0x7E, [.command, .option], true),
            (.arrange, "Расставить", 0x00, [.command, .option], true),
            (.show, "Показать", 0x01, [.command, .option], true),
            (.scroll, "Прокрутить", 0x02, [.command, .option], true),
        ]
        // Порядок прежнего меню держит id Carbon-хоткеев (индекс + 1): строки не переставлять и не вынимать.
        XCTAssertEqual(Hotkeys.entries.map { $0.command },
                       [.workflow, .newChat, .newWindow, .popoutWindow, .expand, .collapse,
                        .cashout, .arrange, .show, .scroll])
        for command in [ClaudeCommand.workflow, .popoutWindow] {
            XCTAssertNil(Hotkeys.entry(for: command)?.key)
            XCTAssertEqual(Hotkeys.entry(for: command)?.registersHotkey, false)
        }
        for (command, title, code, mods, registers) in expected {
            let entry = Hotkeys.entry(for: command)
            XCTAssertEqual(entry?.title, title)
            XCTAssertEqual(entry?.key?.keyCode, code)
            XCTAssertEqual(entry?.key?.mods, mods)
            XCTAssertEqual(entry?.registersHotkey, registers)
        }
    }

    func testCarbonModifiers() {
        XCTAssertEqual(KeyMods([.command, .shift]).carbon, 0x0100 | 0x0200)
        XCTAssertEqual(KeyMods([.command, .option]).carbon, 0x0100 | 0x0800)
        XCTAssertEqual(Hotkeys.quitKey.keyCode, 0x0C)
        XCTAssertEqual(Hotkeys.quitKey.mods, [.command])
    }

    // MARK: - command.json

    func testPayloadMatchesLoaderContract() throws {
        let at = Date(timeIntervalSince1970: 1_756_900_000) // 2025-09-03T11:46:40Z
        let body = CommandChannel.payload(action: "cashout", extra: ["title": "Чат \"один\""],
                                          id: "1756900000123-0042", at: at)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertEqual(json["id"] as? String, "1756900000123-0042")
        XCTAssertEqual(json["action"] as? String, "cashout")
        XCTAssertEqual(json["at"] as? String, "2025-09-03T11:46:40Z")
        XCTAssertEqual(json["title"] as? String, "Чат \"один\"")
        XCTAssertTrue(body.hasPrefix("{\"id\":"), body)
    }

    func testJSONStringEscapesControls() {
        XCTAssertEqual(CommandChannel.jsonString("a\"b\\c"), "\"a\\\"b\\\\c\"")
        XCTAssertEqual(CommandChannel.jsonString("a\nb"), "\"a\\u000ab\"")
    }

    func testAtomicWriteReplacesFile() throws {
        // Живой ~/Library не трогаем: пишем во временную папку.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudeax-\(UUID().uuidString)", isDirectory: true)
        let file = dir.appendingPathComponent("command.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertTrue(CommandChannel.writeAtomic(file, "{\"id\":\"1\"}")) // папки ещё нет
        XCTAssertTrue(CommandChannel.writeAtomic(file, "{\"id\":\"2\"}")) // поверх существующего
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "{\"id\":\"2\"}")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.appendingPathExtension("tmp").path))
    }

    /// Тест гонки (критик п. 1 плана WF9): лоадер читает command.json раз в 500 мс, поэтому
    /// две записи подряд потеряли бы первую. Часы и таймер подставлены, живой ~/Library не трогаем.
    func testQueueKeepsSixHundredMillisecondsBetweenWrites() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudeax-\(UUID().uuidString)", isDirectory: true)
        let file = dir.appendingPathComponent("command.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        let start = Date(timeIntervalSince1970: 1_756_900_000)
        var now = start
        var timers: [(at: Date, block: () -> Void)] = []
        let channel = CommandChannel(path: file, now: { now },
                                     schedule: { delay, block in
                                         timers.append((now.addingTimeInterval(delay), block))
                                     })
        func action() throws -> String {
            let json = try JSONSerialization.jsonObject(with: try Data(contentsOf: file))
            return try XCTUnwrap((json as? [String: Any])?["action"] as? String)
        }
        /// Прокрутить часы до ближайшего таймера и выполнить его — как сделал бы главный поток.
        func tick() throws {
            let timer = try XCTUnwrap(timers.first, "таймер не поставлен")
            timers.removeFirst()
            now = max(now, timer.at)
            timer.block()
        }

        // Две команды меню за 100 мс: первая на диске сразу, вторая ждёт своей очереди.
        XCTAssertTrue(channel.write(action: "collapse"))
        XCTAssertEqual(try action(), "collapse")
        now = now.addingTimeInterval(0.1)
        XCTAssertTrue(channel.write(action: "expand"))
        XCTAssertEqual(try action(), "collapse", "вторая запись затёрла первую")
        try tick()
        XCTAssertEqual(try action(), "expand")
        XCTAssertGreaterThanOrEqual(now.timeIntervalSince(start), CommandChannel.minInterval)

        // Сводка — низший приоритет: ждёт очереди и пропадает, когда пришла команда меню.
        var statusWritten: Bool?
        let expandAt = now
        channel.write(action: "status", fields: [], completion: { statusWritten = $0 })
        XCTAssertEqual(try action(), "expand")
        XCTAssertNil(statusWritten)
        channel.write(action: "scroll")
        XCTAssertEqual(statusWritten, false, "сводку не вытеснила команда меню")

        // Примерка через 0,1 с после команды не пишется (z4-r06): лоадер её ещё не прочитал.
        let preview: [(key: String, value: CommandValue)] = [(key: "preview", value: .bool(true))]
        now = now.addingTimeInterval(0.1)
        XCTAssertFalse(channel.write(action: "theme", fields: preview, priority: .preview))
        XCTAssertEqual(try action(), "expand", "примерка затёрла непрочитанную команду")
        try tick()
        XCTAssertEqual(try action(), "scroll")
        XCTAssertGreaterThanOrEqual(now.timeIntervalSince(expandAt), CommandChannel.minInterval)

        // Через 0,6 с — вне очереди, пишется сразу; команда после неё ждёт те же 600 мс.
        now = now.addingTimeInterval(CommandChannel.minInterval)
        let previewAt = now
        XCTAssertTrue(channel.write(action: "theme", fields: preview, priority: .preview))
        XCTAssertEqual(try action(), "theme")
        channel.write(action: "collapse")
        XCTAssertEqual(try action(), "theme", "команда затёрла примерку раньше срока")
        try tick()
        XCTAssertEqual(try action(), "collapse")
        XCTAssertGreaterThanOrEqual(now.timeIntervalSince(previewAt), CommandChannel.minInterval)
        XCTAssertEqual(channel.lastCommand.hasPrefix("collapse @"), true, channel.lastCommand)
    }

    func testIDsDifferWithinTheSameMillisecond() {
        // Лоадер отбрасывает команду с прежним id, поэтому две подряд обязаны отличаться.
        let ids = Set((0..<200).map { _ in CommandChannel.makeID() })
        XCTAssertGreaterThan(ids.count, 150)
    }

    // MARK: - темы

    /// Мини-каталог формата themes.json: две годные темы и две кривые (без id, без палитры).
    private static let miniCatalog = """
    {"version":1,"themes":[
      {"id":"violet","name":"Фиолетовая","type":"dark","palette":{"accent":"#a78bfa",\
    "background":"#1b1626","foreground":"#ece9f5","sidebar":"#151021","panel":"#241d33","muted":"#8b81a6"}},
      {"id":"arctic","name":"Арктика","type":"light","palette":{"accent":"#2563eb",\
    "background":"#f7f9fc","foreground":"#101828","sidebar":"#eef2f8","panel":"#ffffff","muted":"#667085"}},
      {"id":"","name":"Без id","type":"dark","palette":{"accent":"#000000"}},
      {"id":"broken","name":"Без палитры","type":"dark"},
      {"id":"mango","name":"Манго","type":"dark","set":"bright","palette":{"accent":"#fd8b27",\
    "background":"#512b15","foreground":"#fce9de","sidebar":"#3a1d0c","panel":"#6b3c22","muted":"#be8c6f"}}
    ]}
    """

    private func catalog() -> [Theme] { ThemeCatalog.parse(Data(ClaudeAXTests.miniCatalog.utf8)) }

    func testCatalogParsesThemesAndSkipsBroken() {
        let themes = catalog()
        XCTAssertEqual(themes.map { $0.id }, ["violet", "arctic", "mango"])
        XCTAssertEqual(themes[0].name, "Фиолетовая")
        XCTAssertEqual(themes[0].palette["background"], "#1b1626")
        XCTAssertEqual(themes[1].type, "light")
        // Набор: поля нет — берётся из `type`, есть — стоит в нём (задача #5801).
        XCTAssertEqual(themes.map { $0.set }, [.dark, .light, .bright])
        XCTAssertTrue(ThemeCatalog.parse(Data("не json".utf8)).isEmpty)
        XCTAssertTrue(ThemeCatalog.parse(Data("{\"version\":1}".utf8)).isEmpty)
        // Нет файла — пустой каталог, а не падение.
        XCTAssertTrue(ThemeCatalog.load(directory: URL(fileURLWithPath: "/nope/\(UUID().uuidString)")).isEmpty)
    }

    func testCatalogLoadsFileFromResourcesDirectory() throws {
        // Так же приложение читает themes.json из Contents/Resources (его кладёт tools/bundle.sh).
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudeax-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(ClaudeAXTests.miniCatalog.utf8).write(to: dir.appendingPathComponent(ThemeCatalog.fileName))
        XCTAssertEqual(ThemeCatalog.load(directory: dir).map { $0.id }, ["violet", "arctic", "mango"])
    }

    /// Живой каталог из репозитория: `claude-patch/themes.json` кладёт в бандл tools/bundle.sh.
    func testBundledThemesGoAroundTheColourWheel() throws {
        // Решение 5 плана WF9: имена по-русски, порядок — по цветовому кругу, id не меняются.
        let themes = ThemeCatalog.load(directory: Repo.root
            .appendingPathComponent("claude-patch", isDirectory: true))
        XCTAssertEqual(themes.map { $0.id },
                       // WF245 (слово Элвиса 11.10.2026): из набора ушли «Красная», «Оранжевая», «Жёлтая»,
                       // «Розовая», «Коричневая», «Персиковая», «Манго», «Мёд», «Лимонад», «Апельсин», «Лайм»
                       // и «Ультрафиолет»; порядок остальных прежний.
                       ["green", "matrix", "teal", "tokyo", "blue",
                        "violet", "dracula", "lilac", "crimson",
                        // «Винная» (#9683, лист 43 ★3.3) — красная рядом с «Малиновой» по кругу.
                        "wine", "gray",
                        // «Вкуснофф» (задача #6025) — цвета сайта vkusnoff.kz, в круг она не
                        // встраивается: место ей — последней записью тёмных, чтобы порядок
                        // тёмных до неё остался прежним.
                        "vkusnoff",
                        "lemon", "cream", "mint", "sky", "arctic", "lavender", "sakura",
                        "powder",
                        // Яркие (задача #5801) стоят в хвосте: тёмные и светлые перед ними
                        // идут прежним порядком.
                        "coral", "fuchsia", "electric",
                        // «Opus 5.5» (#7181, вместо «Ночных» #7106) — ещё дальше в хвосте,
                        // по той же причине.
                        "neontokyo", "retrowave", "acid", "abyss", "amber", "malachite",
                        "magma", "laser", "miami", "cobalt"])
        // Меню режет каталог на четыре набора — порядок внутри каждого обязан остаться тем же.
        XCTAssertEqual(themes.filter { $0.set == .dark }.map { $0.name },
                       ["Зелёная", "Матрица", "Бирюзовая",
                        "Токийская ночь", "Синяя", "Фиолетовая", "Дракула", "Сиреневая",
                        "Малиновая", "Винная", "Серая", "Вкуснофф"])
        XCTAssertEqual(themes.filter { $0.set == .light }.map { $0.name },
                       ["Лимонная", "Кремовая", "Мятная", "Небесная", "Светлая",
                        "Лавандовая", "Сакура", "Пудровая"])
        XCTAssertEqual(themes.filter { $0.set == .bright }.map { $0.name },
                       ["Коралл", "Фуксия", "Электрик"])
        XCTAssertEqual(themes.filter { $0.set == .opus }.map { $0.name },
                       ["Неоновый Токио", "Ретровейв", "Кислота", "Бездна", "Янтарный терминал",
                        "Малахит", "Магма", "Лазер", "Майами", "Кобальт"])
        XCTAssertTrue(themes.filter { $0.set == .opus }.allSatisfy { $0.type != "light" }, "Opus 5.5 — тёмные")
        // Слово Элвиса «не повторяй»: ни одна новая палитра не совпадает с прежними ни фоном,
        // ни акцентом.
        let opus = themes.filter { $0.set == .opus }
        let others = themes.filter { $0.set != .opus }
        for theme in opus {
            XCTAssertFalse(others.contains { $0.palette["background"] == theme.palette["background"] },
                           "фон «\(theme.name)» уже есть в каталоге")
            XCTAssertFalse(others.contains { $0.palette["accent"] == theme.palette["accent"] },
                           "акцент «\(theme.name)» уже есть в каталоге")
        }
        // Наборов ровно четыре, «Opus 5.5» последним — три прежних списка на своих местах.
        XCTAssertEqual(ThemeSet.allCases, [.dark, .light, .bright, .opus])
        // Набор — дело меню, `type` — дело страницы. Ярких светлых («Лимонад», «Апельсин») с WF245 в наборе нет.
        XCTAssertEqual(themes.filter { $0.set == .bright && $0.type == "light" }.map { $0.id }, [])
        // Английских имён не осталось (Matrix, Dracula, Tokyo Night), палитра у всех полная.
        for theme in themes {
            XCTAssertEqual(Set(theme.palette.keys), Set(Theme.paletteOrder), theme.id)
            let first = try XCTUnwrap(theme.name.unicodeScalars.first)
            XCTAssertTrue((0x410...0x44F).contains(Int(first.value)), "имя «\(theme.name)» не по-русски")
        }
    }

    /// Шрифт для команды: моноширинный, семейство — голым именем (контракт п. 5).
    private static let monoFont = Font(id: "sf-mono", family: "SF Mono", category: .mono, displayName: "SF Mono")

    private func themeBody(theme: Layer<Theme>, font: Layer<Font>,
                           size: SizeLayer = .keep, frame: Layer<Bool> = .keep,
                           scope: String = MenuModel.themeScopeWindow, title: String = "Vkusnoff",
                           preview: Bool? = nil,
                           id: String = "1756900000123-0042",
                           at: TimeInterval = 1_756_900_000) -> String {
        CommandChannel.payload(action: "theme",
                               fields: ClaudeActions.themeFields(scope: scope, title: title,
                                                                 preview: preview,
                                                                 theme: theme, font: font,
                                                                 size: size, frame: frame),
                               id: id, at: Date(timeIntervalSince1970: at))
    }

    func testThemePayloadMatchesContract() throws {
        // Побайтно, контракт п. 5 плана WF6: id, action, at, scope, title, theme, font;
        // слоя, которого не трогаем, в команде нет вовсе.
        let head = "{\"id\":\"1756900000123-0042\",\"action\":\"theme\",\"at\":\"2025-09-03T11:46:40Z\","
            + "\"scope\":\"window\",\"title\":\"Vkusnoff\""
        let themeField = ",\"theme\":{\"id\":\"violet\",\"name\":\"Фиолетовая\",\"type\":\"dark\","
            + "\"palette\":{\"accent\":\"#a78bfa\",\"background\":\"#1b1626\",\"foreground\":\"#ece9f5\","
            + "\"sidebar\":\"#151021\",\"panel\":\"#241d33\",\"muted\":\"#8b81a6\"}}"
        let fontField = ",\"font\":{\"id\":\"sf-mono\",\"family\":\"SF Mono\",\"mono\":true}"
        let violet = catalog()[0]
        let font = ClaudeAXTests.monoFont

        // 1. Только тема.
        XCTAssertEqual(themeBody(theme: .set(violet), font: .keep), head + themeField + "}")
        // 2. Только шрифт.
        XCTAssertEqual(themeBody(theme: .keep, font: .set(font)), head + fontField + "}")
        // 3. Оба слоя (своя тема) — тема всегда перед шрифтом.
        XCTAssertEqual(themeBody(theme: .set(violet), font: .set(font)), head + themeField + fontField + "}")

        let json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(themeBody(theme: .set(violet), font: .set(font)).utf8)) as? [String: Any])
        XCTAssertEqual(json["action"] as? String, "theme")
        XCTAssertEqual(json["scope"] as? String, "window")
        XCTAssertEqual(json["title"] as? String, "Vkusnoff")
        let theme = try XCTUnwrap(json["theme"] as? [String: Any])
        XCTAssertEqual(theme["id"] as? String, "violet")
        XCTAssertEqual(theme["type"] as? String, "dark")
        XCTAssertEqual((theme["palette"] as? [String: String])?["background"], "#1b1626")
        let fontJSON = try XCTUnwrap(json["font"] as? [String: Any])
        XCTAssertEqual(fontJSON["family"] as? String, "SF Mono")
        XCTAssertEqual(fontJSON["mono"] as? Bool, true)
    }

    func testThemeResetPayloadCarriesNull() throws {
        // Сброс обоих слоёв «всем окнам».
        let body = themeBody(theme: .reset, font: .reset, scope: MenuModel.themeScopeAll, title: "",
                             id: "1-0001", at: 0)
        XCTAssertTrue(body.hasSuffix("\"scope\":\"all\",\"title\":\"\",\"theme\":null,\"font\":null}"), body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertTrue(json["theme"] is NSNull)
        XCTAssertTrue(json["font"] is NSNull)

        // Сброс ОДНОГО слоя: «Системный (как у Claude)» не должен трогать тему окна.
        let fontOnly = themeBody(theme: .keep, font: .reset, id: "1-0001", at: 0)
        XCTAssertEqual(fontOnly, "{\"id\":\"1-0001\",\"action\":\"theme\",\"at\":\"1970-01-01T00:00:00Z\","
            + "\"scope\":\"window\",\"title\":\"Vkusnoff\",\"font\":null}")
        // И наоборот — «Как у Claude» в теме не трогает шрифт.
        XCTAssertEqual(themeBody(theme: .reset, font: .keep, id: "1-0001", at: 0),
                       "{\"id\":\"1-0001\",\"action\":\"theme\",\"at\":\"1970-01-01T00:00:00Z\","
                       + "\"scope\":\"window\",\"title\":\"Vkusnoff\",\"theme\":null}")
        // Оба слоя «не трогать» — команды нет вообще.
        XCTAssertEqual(ClaudeActions.themeFields(scope: "window", title: "", theme: .keep, font: .keep).count, 2)

        // Старые команды не поехали: extra по-прежнему пишет строки по алфавиту.
        XCTAssertEqual(CommandChannel.payload(action: "scroll", extra: [:], id: "1-0001",
                                              at: Date(timeIntervalSince1970: 0)),
                       "{\"id\":\"1-0001\",\"action\":\"scroll\",\"at\":\"1970-01-01T00:00:00Z\"}")
    }

    func testSizeAndFramePayloadMatchContract() throws {
        // Побайтно, контракт п. 1 плана WF12 с расширением решения 1 плана WF19: id, action, at,
        // scope, title, theme, font, size, frame. Размер — числа, а не строки; рамка — true;
        // слоя, которого не трогаем, в команде нет; снятая ПОЛОВИНА размера — null внутри объекта.
        let head = "{\"id\":\"1756900000123-0042\",\"action\":\"theme\",\"at\":\"2025-09-03T11:46:40Z\","
            + "\"scope\":\"window\",\"title\":\"Vkusnoff\""
        let themeField = ",\"theme\":{\"id\":\"violet\",\"name\":\"Фиолетовая\",\"type\":\"dark\","
            + "\"palette\":{\"accent\":\"#a78bfa\",\"background\":\"#1b1626\",\"foreground\":\"#ece9f5\","
            + "\"sidebar\":\"#151021\",\"panel\":\"#241d33\",\"muted\":\"#8b81a6\"}}"
        let fontField = ",\"font\":{\"id\":\"sf-mono\",\"family\":\"SF Mono\",\"mono\":true}"
        let violet = catalog()[0]
        let font = ClaudeAXTests.monoFont

        // 1. Только размер — и только та половина, которую выбрали в меню.
        XCTAssertEqual(themeBody(theme: .keep, font: .keep, size: .one(.answer, .set(16))),
                       head + ",\"size\":{\"answer\":16}}")
        XCTAssertEqual(themeBody(theme: .keep, font: .keep, size: .one(.question, .set(13))),
                       head + ",\"size\":{\"question\":13}}")
        // 2. Только рамка.
        XCTAssertEqual(themeBody(theme: .keep, font: .keep, frame: .set(true)), head + ",\"frame\":true}")
        // 3. Все четыре слоя (своя тема со всем сохранённым) — порядок тема, шрифт, размер, рамка.
        let sizeField = ",\"size\":{\"answer\":16,\"question\":14}"
        let full = themeBody(theme: .set(violet), font: .set(font),
                             size: SizeLayer(Size(answer: 16, question: 14)), frame: .set(true))
        XCTAssertEqual(full, head + themeField + fontField + sizeField + ",\"frame\":true}")

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(full.utf8)) as? [String: Any])
        let size = try XCTUnwrap(json["size"] as? [String: Any])
        XCTAssertEqual(size["answer"] as? Int, 16)   // именно число, а не строка
        XCTAssertEqual(size["question"] as? Int, 14)
        XCTAssertEqual(json["frame"] as? Bool, true)

        // 4. Сброс слоя — null; размер снимается целиком, обеими половинами («🧹 Всё как у Claude»).
        XCTAssertEqual(themeBody(theme: .keep, font: .keep, size: .reset), head + ",\"size\":null}")
        XCTAssertEqual(themeBody(theme: .keep, font: .keep, frame: .reset), head + ",\"frame\":null}")
        let reset = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(themeBody(theme: .keep, font: .keep, size: .reset, frame: .reset).utf8)) as? [String: Any])
        XCTAssertTrue(reset["size"] is NSNull)
        XCTAssertTrue(reset["frame"] is NSNull)
        // Тема и шрифт при этом не поехали.
        XCTAssertNil(reset["theme"])
        XCTAssertNil(reset["font"])

        // 4а. «Как у Claude» в одном из двух подменю снимает СВОЮ половину — null внутри объекта
        // (решение 1 плана WF19); вторая половина в команду не попадает вовсе.
        XCTAssertEqual(themeBody(theme: .keep, font: .keep, size: .one(.answer, .reset)),
                       head + ",\"size\":{\"answer\":null}}")
        XCTAssertEqual(themeBody(theme: .keep, font: .keep, size: .one(.question, .reset)),
                       head + ",\"size\":{\"question\":null}}")
        let half = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(themeBody(theme: .keep, font: .keep, size: .one(.answer, .reset)).utf8)) as? [String: Any])
        let halves = try XCTUnwrap(half["size"] as? [String: Any])
        XCTAssertTrue(halves["answer"] is NSNull, "снятая половина — именно null, а не 0")
        XCTAssertNil(halves["question"], "вторую половину команда не трогает")
        // Обе половины «не трогать» — поля size нет вовсе (пустой объект страница прочла бы
        // как полный сброс).
        XCTAssertEqual(themeBody(theme: .keep, font: .keep,
                                 size: .halves(answer: .keep, question: .keep)), head + "}")
        XCTAssertEqual(themeBody(theme: .keep, font: .keep, size: SizeLayer(Size())), head + "}")
        // Одна снята, вторая задана — порядок ключей прежний, ответы первыми.
        XCTAssertEqual(themeBody(theme: .keep, font: .keep,
                                 size: .halves(answer: .set(16), question: .reset)),
                       head + ",\"size\":{\"answer\":16,\"question\":null}}")

        // 5. Примерка размера — то же тело плюс preview перед слоями.
        XCTAssertEqual(themeBody(theme: .keep, font: .keep, size: .one(.answer, .set(20)), preview: true),
                       head + ",\"preview\":true,\"size\":{\"answer\":20}}")
        XCTAssertEqual(themeBody(theme: .keep, font: .keep, size: .one(.question, .reset), preview: true),
                       head + ",\"preview\":true,\"size\":{\"question\":null}}")
        XCTAssertEqual(themeBody(theme: .keep, font: .keep, frame: .set(true), preview: true),
                       head + ",\"preview\":true,\"frame\":true}")

        // 6. Границы контракта 11…24.
        XCTAssertEqual(Size(answer: 40, question: 3).commandValue.json,
                       "{\"answer\":24,\"question\":11}")
        XCTAssertTrue(Size().isEmpty)
        XCTAssertFalse(Size(question: 12).isEmpty)
        XCTAssertEqual(Size.one(.answer, 15), Size(answer: 15))
        XCTAssertEqual(Size.one(.question, 15), Size(question: 15))
        XCTAssertEqual(Size(answer: 15, question: 12).value(.question), 12)
        XCTAssertEqual(CommandValue.number(12).json, "12")
    }

    func testPreviewPayloadMatchesContract() throws {
        // Побайтно, контракт п. 1 плана WF8: preview стоит между title и слоями,
        // в примерке слой ровно один, «конец предпросмотра» — без слоёв вовсе.
        let head = "{\"id\":\"1756900000123-0042\",\"action\":\"theme\",\"at\":\"2025-09-03T11:46:40Z\","
            + "\"scope\":\"window\",\"title\":\"Vkusnoff\""
        let violet = catalog()[0]

        // 1. Примерка темы — тело закрепляющей команды плюс "preview":true перед слоем.
        let preview = themeBody(theme: .set(violet), font: .keep, preview: true)
        XCTAssertEqual(preview, themeBody(theme: .set(violet), font: .keep)
            .replacingOccurrences(of: head, with: head + ",\"preview\":true"))
        XCTAssertTrue(preview.hasPrefix(head + ",\"preview\":true,\"theme\":{\"id\":\"violet\","), preview)

        // 2. Примерка сброса шрифта («Системный») — слой уходит как null.
        XCTAssertEqual(themeBody(theme: .keep, font: .reset, preview: true),
                       head + ",\"preview\":true,\"font\":null}")

        // 3. Конец предпросмотра — preview: false и ни одного слоя.
        let end = themeBody(theme: .keep, font: .keep, preview: false)
        XCTAssertEqual(end, head + ",\"preview\":false}")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(end.utf8)) as? [String: Any])
        XCTAssertEqual(json["preview"] as? Bool, false)
        XCTAssertEqual(json["scope"] as? String, "window")
        XCTAssertNil(json["theme"])
        XCTAssertNil(json["font"])

        // Закрепляющая команда поля preview не носит вовсе.
        XCTAssertFalse(themeBody(theme: .set(violet), font: .keep).contains("\"preview\""))
    }

    func testCommandValueWritesBooleans() {
        XCTAssertEqual(CommandValue.bool(true).json, "true")
        XCTAssertEqual(CommandValue.bool(false).json, "false")
        XCTAssertEqual(CommandValue.object([(key: "mono", value: .bool(false))]).json, "{\"mono\":false}")
        XCTAssertEqual(Font(id: "georgia", family: "Georgia", category: .serif, displayName: "Джорджия")
            .commandValue.json, "{\"id\":\"georgia\",\"family\":\"Georgia\",\"mono\":false}")
    }

    /// Своя тема из my-themes.json: фиолетовая палитра + моноширинный шрифт.
    private func myTheme() -> MyTheme {
        MyTheme(id: "user-1756900000000", name: "Моя тёплая", type: "dark",
                palette: catalog()[0].palette, font: ClaudeAXTests.monoFont)
    }

    /// Меню (с WF237 — меню голосов Диктатора и меню файла, `MenuKit`) поднимается только после того, как активность
    /// ПРАВДА приехала (#5797): `activate` её лишь просит, а меню, поднятое до приезда, AppKit гасит через четверть
    /// секунды — Элвис видел «мигнуло и пропало».
    func testMenuWaitsUntilAppIsReallyActive() {
        // Уже активны — ни одного шага ожидания, меню поднимается сразу.
        var pumps = 0
        var clock: TimeInterval = 100
        XCTAssertTrue(MenuKit.awaitActive(isActive: { true }, pump: { pumps += 1 },
                                               now: { clock }))
        XCTAssertEqual(pumps, 0)

        // Активность приезжает с третьего события — дождались, лишнего не ждём.
        pumps = 0
        XCTAssertTrue(MenuKit.awaitActive(isActive: { pumps >= 3 },
                                               pump: { pumps += 1; clock += 0.02 },
                                               now: { clock }))
        XCTAssertEqual(pumps, 3)

        // Не приехала вовсе — выходим по сроку и меню поднимаем всё равно (ответ false).
        pumps = 0
        clock = 100
        XCTAssertFalse(MenuKit.awaitActive(isActive: { false },
                                                pump: { pumps += 1; clock += MenuKit.activateStep },
                                                now: { clock }))
        XCTAssertEqual(clock - 100, MenuKit.activateWait, accuracy: MenuKit.activateStep,
                       "ждали дольше срока")
        XCTAssertGreaterThan(pumps, 0)
        XCTAssertLessThanOrEqual(pumps,
                                 Int((MenuKit.activateWait / MenuKit.activateStep).rounded()) + 1)
    }

    // MARK: - канал и действия на временной папке

    /// Своя тема со всеми слоями — ровно такая «Пудра» и подменяла окну шрифт и кегль.
    private func loadedMyTheme() -> MyTheme {
        MyTheme(id: "user-1757000000000", name: "Пудра", type: "light",
                palette: catalog()[1].palette, font: ClaudeAXTests.monoFont,
                size: Size(answer: 20, question: 13), frame: true)
    }

    /// Тело команды без `id` и времени: у двух записей они разные, сравнивать нечего.
    private static func commandTail(_ text: String) -> String {
        guard let scope = text.range(of: ",\"scope\":") else { return text }
        return String(text[scope.lowerBound...])
    }

    /// Канал и действия на временной папке — образец из теста живых цветов.
    private func actionsOnDisk(dir: URL, now: @escaping () -> Date) -> ClaudeActions {
        let actions = ClaudeActions(app: IsolatedClaudeApp.make(),
                                    commands: CommandChannel(path: dir.appendingPathComponent("command.json"),
                                                             now: now, schedule: { _, _ in }),
                                    themes: [], fonts: [],
                                    themeStore: ThemeStore(defaults: MemoryThemeDefaults()),
                                    myThemes: MyThemesStore(url: dir.appendingPathComponent("my.json")))
        actions.clock = now
        return actions
    }

    /// Слой размера словами: «16/—» — ответам 16, вопросы не трогаем; «∅» — половину снимаем;
    /// «сброс слоя» — `"size":null` целиком.
    private func describe(_ size: SizeLayer) -> String {
        if case .reset = size { return "сброс слоя" }
        func half(_ side: Size.Half) -> String {
            switch size.half(side) {
            case .keep: return "—"
            case .reset: return "∅"
            case .set(let px): return String(px)
            }
        }
        return "\(half(.answer))/\(half(.question))"
    }

    func testLookLayerGoesAfterFrameWhole() throws {
        // Контракт плана WF83: поле `look` ПОСЛЕ `frame`, объект целиком `{aurora, neon, dense}`,
        // сброс — null; у примерки `preview` стоит перед слоями, как у остальных.
        let head = "{\"id\":\"1756900000123-0042\",\"action\":\"theme\",\"at\":\"2025-09-03T11:46:40Z\","
            + "\"scope\":\"window\",\"title\":\"Vkusnoff\""
        func body(frame: Layer<Bool> = .keep, look: Layer<Look>, preview: Bool? = nil) -> String {
            CommandChannel.payload(action: "theme",
                                   fields: ClaudeActions.themeFields(scope: MenuModel.themeScopeWindow,
                                                                     title: "Vkusnoff", preview: preview,
                                                                     theme: .keep, font: .keep,
                                                                     frame: frame, look: look),
                                   id: "1756900000123-0042",
                                   at: Date(timeIntervalSince1970: 1_756_900_000))
        }
        XCTAssertEqual(body(frame: .set(true), look: .set(Look(aurora: true, dense: true))),
                       head + ",\"frame\":true,\"look\":{\"aurora\":true,\"neon\":false,\"dense\":true}}")
        XCTAssertEqual(body(look: .reset), head + ",\"look\":null}")
        XCTAssertEqual(body(look: .keep), head + "}")
        XCTAssertEqual(body(look: .set(Look(dense: true)), preview: true),
                       head + ",\"preview\":true,\"look\":{\"aurora\":false,\"neon\":false,\"dense\":true}}")
        // WF220: снятый `neon` из старых записей не читается — вид без него.
        XCTAssertEqual(Look.from(["neon": true, "dense": true]), Look(dense: true))
        XCTAssertEqual(Look.from(["neon": true])?.layer, .reset)
        // Пустой вид — это сброс слоя, а не три false.
        XCTAssertEqual(Look().layer, .reset)
        XCTAssertEqual(Look(dense: true).layer, .set(Look(dense: true)))
        // `new-window` вида не шлёт: слоя в нём нет вовсе.
        XCTAssertFalse(ClaudeActions.newWindowFields(title: "", x: 0, y: 0, text: "")
            .contains { $0.key == "look" })
    }

    /// WF237: оформление окон переехало из меню жёлтой кнопки в «Оформление» панели — гарантия меню «пункт трогает
    /// ровно свой слой» теперь на пути панели: «Плотный текст» шлёт только `look`, «Шрифт» — только `font`,
    /// «Размер» — только половину `answer`; всё — `scope:"all"`, и выбор ложится в память «всем окнам».
    func testPanelRowsTouchOnlyTheirLayer() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudeax-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ThemeStore(defaults: MemoryThemeDefaults())
        let file = dir.appendingPathComponent("command.json")
        // Канал на каждый шаг свой: очередь общего канала ждала бы 600 мс расписания, которого в тесте нет.
        func sent(_ step: (ClaudeActions) -> Bool) throws -> String? {
            try? FileManager.default.removeItem(at: file)
            let actions = ClaudeActions(app: IsolatedClaudeApp.make(),
                                        commands: CommandChannel(path: file, now: Date.init, schedule: { _, _ in }),
                                        themes: [], fonts: [ClaudeAXTests.monoFont], themeStore: store,
                                        myThemes: MyThemesStore(url: dir.appendingPathComponent("my.json")))
            guard step(actions) else { return nil }
            return ClaudeAXTests.commandTail(try String(contentsOf: file, encoding: .utf8))
        }

        XCTAssertEqual(try sent { $0.setAllDense(true) },
                       ",\"scope\":\"all\",\"title\":\"\",\"look\":{\"aurora\":false,\"neon\":false,\"dense\":true}}")
        XCTAssertTrue(store.allLook.dense)
        XCTAssertNil(try sent { $0.setAllDense(true) }, "уже включён — команды нет")
        XCTAssertEqual(try sent { $0.setAllFont(id: "sf-mono") },
                       ",\"scope\":\"all\",\"title\":\"\",\"font\":{\"id\":\"sf-mono\",\"family\":\"SF Mono\",\"mono\":true}}")
        XCTAssertEqual(store.allFontID, "sf-mono")
        XCTAssertNil(try sent { $0.setAllFont(id: "papyrus") }, "шрифта нет в каталоге — молчим")
        XCTAssertEqual(try sent { $0.setAllTextSize(16) }, ",\"scope\":\"all\",\"title\":\"\",\"size\":{\"answer\":16}}")
        XCTAssertEqual(store.allSize, Size(answer: 16))
        // «Как у Claude» снимает ровно свою половину и свой слой.
        XCTAssertEqual(try sent { $0.setAllTextSize(nil) }, ",\"scope\":\"all\",\"title\":\"\",\"size\":{\"answer\":null}}")
        XCTAssertEqual(try sent { $0.setAllFont(id: nil) }, ",\"scope\":\"all\",\"title\":\"\",\"font\":null}")
        // Плотный — последний эффект: выключение снимает слой вида целиком.
        XCTAssertEqual(try sent { $0.setAllDense(false) }, ",\"scope\":\"all\",\"title\":\"\",\"look\":null}")
        XCTAssertFalse(store.allLook.dense)
    }

    func testThemeStoreRemembersLook() {
        let defaults = MemoryThemeDefaults()
        let store = ThemeStore(defaults: defaults)
        XCTAssertEqual(store.windowLook(title: "Vkusnoff"), Look())
        XCTAssertEqual(store.allLook, Look())
        store.setWindowLook(Look(aurora: true, dense: true), title: "Vkusnoff")
        store.setAllLook(Look(dense: true))
        XCTAssertEqual(store.windowLook(title: "Vkusnoff"), Look(aurora: true, dense: true))
        XCTAssertEqual(store.allLook, Look(dense: true))
        XCTAssertEqual(defaults.values[ThemeStore.lookByWindowKey] as? [String: [String: Bool]],
                       ["Vkusnoff": ["aurora": true, "dense": true]])
        // Пустой вид — записи нет, как у выключенной рамки.
        store.setWindowLook(Look(), title: "Vkusnoff")
        XCTAssertNil(defaults.values[ThemeStore.lookByWindowKey])
        store.setAllLook(nil)
        XCTAssertNil(defaults.values[ThemeStore.lookAllKey])
        // «Всем окнам» чистит только свой слой; окно без заголовка запоминать нечем.
        store.setWindowLook(Look(dense: true), title: "Trelvis")
        store.setWindowTheme("blue", title: "Trelvis")
        store.clearWindowLooks()
        XCTAssertEqual(store.windowLook(title: "Trelvis"), Look())
        XCTAssertEqual(store.windowThemeID(title: "Trelvis"), "blue")
        store.setWindowLook(Look(dense: true), title: "")
        XCTAssertEqual(store.windowLook(title: ""), Look())
    }

    func testThemeStoreRemembersChoicePerWindow() {
        let defaults = MemoryThemeDefaults()
        let store = ThemeStore(defaults: defaults)
        XCTAssertNil(store.windowThemeID(title: "Vkusnoff"))
        store.setWindowTheme("orange", title: "Vkusnoff")
        store.setWindowTheme("blue", title: "Trelvis")
        store.setAllTheme("matrix")
        XCTAssertEqual(store.windowThemeID(title: "Vkusnoff"), "orange")
        XCTAssertEqual(store.allThemeID, "matrix")
        XCTAssertEqual(defaults.values[ThemeStore.byWindowKey] as? [String: String],
                       ["Vkusnoff": "orange", "Trelvis": "blue"])
        store.setWindowTheme(nil, title: "Vkusnoff") // «Как у Claude»
        XCTAssertNil(store.windowThemeID(title: "Vkusnoff"))
        XCTAssertEqual(store.windowThemeID(title: "Trelvis"), "blue")
        store.setAllTheme(nil)
        XCTAssertNil(store.allThemeID)
        // «Тема всех окон» стирает карту окон — как runThemeCommand в inject.js.
        store.clearWindowThemes()
        XCTAssertNil(store.windowThemeID(title: "Trelvis"))
        // Окно без заголовка запоминать нечем: страница адресует его как «в фокусе».
        store.setWindowTheme("blue", title: "")
        XCTAssertNil(store.windowThemeID(title: ""))
    }

    func testThemeStoreKeepsThemeAndFontApart() {
        let defaults = MemoryThemeDefaults()
        let store = ThemeStore(defaults: defaults)
        store.setWindowTheme("violet", title: "Vkusnoff")
        store.setWindowFont("sf-mono", title: "Vkusnoff")
        store.setAllTheme("matrix")
        store.setAllFont("georgia")
        XCTAssertEqual(store.windowThemeID(title: "Vkusnoff"), "violet")
        XCTAssertEqual(store.windowFontID(title: "Vkusnoff"), "sf-mono")
        XCTAssertEqual(defaults.values[ThemeStore.fontByWindowKey] as? [String: String],
                       ["Vkusnoff": "sf-mono"])

        // «Тема всем окнам» чистит только карту тем — шрифты окон остаются (контракт п. 5).
        store.clearWindowThemes()
        XCTAssertNil(store.windowThemeID(title: "Vkusnoff"))
        XCTAssertEqual(store.windowFontID(title: "Vkusnoff"), "sf-mono")
        store.clearWindowFonts()
        XCTAssertNil(store.windowFontID(title: "Vkusnoff"))

        // Слои «всем окнам» тоже независимы.
        store.setAllFont(nil)
        XCTAssertNil(store.allFontID)
        XCTAssertEqual(store.allThemeID, "matrix")
        // Окно без заголовка запоминать нечем.
        store.setWindowFont("sf-mono", title: "")
        XCTAssertNil(store.windowFontID(title: ""))
    }

    func testThemeStoreRemembersSize() {
        // План WF12 п. 1: размер — такой же независимый слой, со своими ключами (рамка снята в WF220).
        let defaults = MemoryThemeDefaults()
        let store = ThemeStore(defaults: defaults)
        XCTAssertNil(store.windowSize(title: "Vkusnoff"))
        XCTAssertNil(store.allSize)

        store.setWindowSize(Size(answer: 16, question: 13), title: "Vkusnoff")
        store.setWindowSize(Size(answer: 20), title: "Trelvis")
        store.setAllSize(Size(question: 12))
        XCTAssertEqual(store.windowSize(title: "Vkusnoff"), Size(answer: 16, question: 13))
        XCTAssertEqual(store.windowSize(title: "Trelvis"), Size(answer: 20))
        XCTAssertEqual(store.allSize, Size(question: 12))
        // Ключи — те, что читает живое приложение; половины лежат числами.
        XCTAssertEqual((defaults.values[ThemeStore.sizeByWindowKey] as? [String: Any])?.keys.sorted(),
                       ["Trelvis", "Vkusnoff"])
        XCTAssertEqual(ThemeStore.size(defaults.values[ThemeStore.sizeAllKey])?.question, 12)

        // Сброс слоя: запись пропадает целиком, а не половиной.
        store.setWindowSize(nil, title: "Vkusnoff")
        XCTAssertNil(store.windowSize(title: "Vkusnoff"))
        XCTAssertEqual(store.windowSize(title: "Trelvis"), Size(answer: 20))
        store.setAllSize(nil)
        XCTAssertNil(store.allSize)

        // «Всем окнам» чистит карту только своего слоя (контракт п. 5 плана WF6).
        store.setWindowTheme("violet", title: "Trelvis")
        store.clearWindowSizes()
        XCTAssertNil(store.windowSize(title: "Trelvis"))
        XCTAssertEqual(store.windowThemeID(title: "Trelvis"), "violet")
        XCTAssertEqual(store.windowThemeID(title: "Trelvis"), "violet")

        // Окно без заголовка запоминать нечем; мусор в записи — как будто записи нет.
        store.setWindowSize(Size(answer: 16), title: "")
        XCTAssertNil(store.windowSize(title: ""))
        XCTAssertNil(ThemeStore.size(nil))
        XCTAssertNil(ThemeStore.size("15"))
        XCTAssertNil(ThemeStore.size(["answer": "большой"]))
        XCTAssertEqual(ThemeStore.size(["answer": 99]), Size(answer: Size.maxPx))

        // MARK: что запоминается после команды размера (критик В4 и В5 плана WF19)
        // База слияния у окна — своя запись, а её нет — запись «всем окнам»: страница мержит
        // по той же цепочке и материализует унаследованную половину в запись чата.
        XCTAssertEqual(ClaudeActions.windowSize(after: .one(.answer, .set(16)),
                                                window: nil, all: Size(question: 12)),
                       Size(answer: 16, question: 12))
        XCTAssertEqual(ClaudeActions.windowSize(after: .one(.answer, .set(16)),
                                                window: Size(question: 13), all: Size(question: 12)),
                       Size(answer: 16, question: 13), "своя запись сильнее «всем окнам»")
        // «Как у Claude» в одном подменю снимает свою половину — вторая остаётся.
        XCTAssertEqual(ClaudeActions.windowSize(after: .one(.answer, .reset),
                                                window: Size(answer: 16, question: 13), all: nil),
                       Size(question: 13))
        // Снятая последняя половина — записи больше нет вовсе (страница читает пустой слой так же).
        XCTAssertNil(ClaudeActions.windowSize(after: .one(.question, .reset),
                                              window: Size(question: 13), all: nil))
        // Наследующее окно: снимаем половину, которой у него своей и не было, — остаётся вторая,
        // унаследованная (материализуется числом; открытый риск плана, не баг).
        XCTAssertEqual(ClaudeActions.windowSize(after: .one(.answer, .reset),
                                                window: nil, all: Size(answer: 18, question: 12)),
                       Size(question: 12))
        // «🧹 Всё как у Claude» снимает слой целиком.
        XCTAssertNil(ClaudeActions.windowSize(after: .reset,
                                              window: Size(answer: 16, question: 13),
                                              all: Size(question: 12)))
        // Слой «не трогать» ничего не меняет.
        XCTAssertEqual(ClaudeActions.windowSize(after: .keep, window: Size(answer: 16), all: nil),
                       Size(answer: 16))
        // Та же арифметика слоя размера: снятая половина уходит из записи (критик В5).
        XCTAssertEqual(SizeLayer.one(.answer, .reset).applied(to: Size(answer: 16, question: 14)),
                       Size(question: 14))
        XCTAssertNil(SizeLayer.reset.applied(to: Size(answer: 16, question: 14)))
        XCTAssertEqual(SizeLayer.one(.question, .set(14)).applied(to: Size(answer: 16)),
                       Size(answer: 16, question: 14))
    }

    func testSizeHalfResetKeepsOtherHalf() {
        // Решение 1 плана WF19, чистая проверка слоя команды: три состояния половины.
        XCTAssertNil(SizeLayer.keep.commandValue?.json, "поля size нет вовсе")
        XCTAssertEqual(SizeLayer.reset.commandValue?.json, "null")
        XCTAssertEqual(SizeLayer.one(.answer, .reset).commandValue?.json, "{\"answer\":null}")
        XCTAssertEqual(SizeLayer.one(.question, .reset).commandValue?.json, "{\"question\":null}")
        XCTAssertEqual(SizeLayer.one(.answer, .set(16)).commandValue?.json, "{\"answer\":16}")
        // Порядок ключей прежний — ответы первыми, — чем бы половины ни были.
        XCTAssertEqual(SizeLayer.halves(answer: .set(16), question: .reset).commandValue?.json,
                       "{\"answer\":16,\"question\":null}")
        XCTAssertEqual(SizeLayer.halves(answer: .reset, question: .set(12)).commandValue?.json,
                       "{\"answer\":null,\"question\":12}")
        // Обе половины «не трогать» = слоя в команде нет (иначе страница прочла бы {} как сброс).
        XCTAssertNil(SizeLayer.halves(answer: .keep, question: .keep).commandValue)
        XCTAssertTrue(SizeLayer.halves(answer: .keep, question: .keep).isKeep)
        XCTAssertFalse(SizeLayer.one(.answer, .reset).isKeep, "снятие половины — это команда")
        XCTAssertFalse(SizeLayer.reset.isKeep)

        // Границы контракта 11…24 держатся и здесь: в команду уходит уже обрезанное число.
        XCTAssertEqual(SizeLayer.one(.answer, .set(99)).commandValue?.json, "{\"answer\":24}")
        XCTAssertEqual(SizeLayer.one(.question, .set(3)).commandValue?.json, "{\"question\":11}")

        // Переводы: готовый размер и слой-значение (своя тема, вид проекта).
        XCTAssertEqual(SizeLayer(Size(answer: 16, question: 14)).commandValue?.json,
                       "{\"answer\":16,\"question\":14}")
        XCTAssertNil(SizeLayer(Size()).commandValue, "пустой размер — не слой, а «не трогать»")
        XCTAssertNil(SizeLayer(Layer<Size>.keep).commandValue)
        XCTAssertEqual(SizeLayer(Layer<Size>.reset).commandValue?.json, "null")
        XCTAssertEqual(SizeLayer(Layer<Size>.set(Size(question: 12))).commandValue?.json,
                       "{\"question\":12}")
        XCTAssertNil(SizeLayer(Layer<Size>.set(Size())).commandValue)

        // Половины слоя поимённо — по ним меню и решает, что послать.
        XCTAssertEqual(SizeLayer.one(.answer, .set(16)).half(.answer).value, 16)
        XCTAssertTrue(SizeLayer.one(.answer, .set(16)).half(.question).isKeep)
        // Сброс слоя целиком — это сброс обеих половин.
        XCTAssertFalse(SizeLayer.reset.half(.answer).isKeep)
        XCTAssertFalse(SizeLayer.reset.half(.question).isKeep)
        XCTAssertNil(SizeLayer.reset.half(.question).value)
    }

    // MARK: - шрифты

    func testFontCatalogKeepsInstalledCyrillicFamilies() {
        let installed = ["Georgia", "Verdana", "Papyrus", "Menlo", "Fira Code", "Weird*Mono",
                         "Иван Mono", "Monaco"]
        // Без кириллицы шрифт в меню не показываем.
        let fonts = FontCatalog.build(installed: installed,
                                      coversCyrillic: { !["Papyrus", "Fira Code"].contains($0) },
                                      displayName: { $0 == "Menlo" ? "Менло" : $0 })
        // Обычные — в порядке белого списка; моноширинные следом, тоже по списку.
        XCTAssertEqual(fonts.map { $0.family }, ["Georgia", "Verdana", "Menlo", "Monaco"])
        XCTAssertEqual(fonts.map { $0.mono }, [false, false, true, true])
        XCTAssertEqual(fonts.map { $0.id }, ["georgia", "verdana", "menlo", "monaco"])
        XCTAssertEqual(fonts[2].displayName, "Менло") // localizedNameForFamily только для меню
        // Helvetica Neue из белого списка не стоит — в каталоге её нет.
        XCTAssertFalse(fonts.contains { $0.family == "Helvetica Neue" })

        // Санитайзер контракта: только [A-Za-z0-9 -], ≤ 60 знаков.
        XCTAssertEqual(FontCatalog.sanitize(family: "Comic Sans MS"), "Comic Sans MS")
        XCTAssertNil(FontCatalog.sanitize(family: "Weird*Mono"))
        XCTAssertNil(FontCatalog.sanitize(family: "Иван Mono"))
        XCTAssertNil(FontCatalog.sanitize(family: String(repeating: "a", count: 61)))
        XCTAssertEqual(FontCatalog.id(for: "SF Mono"), "sf-mono")

        // Секция «МОНОШИРИННЫЕ» не разрастается: не больше десяти пунктов.
        let many = (1...14).map { "Test\($0) Mono" }
        let capped = FontCatalog.build(installed: many, coversCyrillic: { _ in true }, displayName: { $0 })
        XCTAssertEqual(capped.count, FontCatalog.monoLimit)
        XCTAssertTrue(capped.allSatisfy { $0.mono })
    }

    func testFontCatalogSplitsFamiliesIntoFourSections() {
        // Решение 7 плана WF9: четыре секции, каждая в порядке своего белого списка. Порядок
        // `FontCategory` не трогаем (на нём каталог); в списке «Шрифт» панели секции идут по `fontSections` —
        // с засечками последними (#6251, слово Элвиса 17.09).
        XCTAssertEqual(FontCategory.allCases, [.serif, .sans, .hand, .mono])
        XCTAssertEqual(PanelColorTiles.fontSections.map { $0.id }, ["sans", "hand", "mono", "serif"])
        XCTAssertEqual(Set(PanelColorTiles.fontSections.map { $0.id }), Set(FontCategory.allCases.map { $0.rawValue }),
                       "секция потерялась")
        XCTAssertEqual(FontCatalog.serifFamilies,
                       ["Georgia", "Palatino", "Baskerville", "Didot", "Hoefler Text",
                        "Iowan Old Style", "Times New Roman"])
        XCTAssertEqual(FontCatalog.sansFamilies,
                       ["Helvetica Neue", "Avenir Next", "Futura", "Gill Sans", "Optima", "Verdana",
                        "Trebuchet MS", "Arial", "Tahoma"])
        // Noteworthy, Bradley Hand и Snell Roundhand убраны — «плохо читаются» (#6251).
        XCTAssertEqual(FontCatalog.handFamilies,
                       ["Comic Sans MS", "Chalkboard SE", "Marker Felt", "Papyrus", "Copperplate",
                        "American Typewriter"])
        for gone in ["Noteworthy", "Bradley Hand", "Snell Roundhand"] {
            XCTAssertFalse(FontCatalog.handFamilies.contains(gone), "\(gone) вернулся в меню")
        }
        // Ни одно семейство не попало в две секции сразу.
        let all = FontCategory.allCases.flatMap { FontCatalog.families($0) }
        XCTAssertEqual(all.count, Set(all).count)

        let installed = ["Georgia", "Times New Roman", "Arial", "Futura", "Papyrus", "Marker Felt",
                         "Menlo", "Monaco"]
        let fonts = FontCatalog.build(installed: installed, coversCyrillic: { _ in true },
                                      displayName: { $0 })
        XCTAssertEqual(fonts.map { $0.family },
                       ["Georgia", "Times New Roman", "Futura", "Arial", "Marker Felt", "Papyrus",
                        "Menlo", "Monaco"])
        XCTAssertEqual(fonts.map { $0.category },
                       [.serif, .serif, .sans, .sans, .hand, .hand, .mono, .mono])
        // В команду по-прежнему уезжает булево mono, а не категория (контракт п. 5 WF6).
        XCTAssertEqual(fonts.map { $0.mono }, [false, false, false, false, false, false, true, true])
        XCTAssertFalse(fonts[0].commandValue.json.contains("serif"))

        // Незнакомое семейство (шрифт из my-themes.json) — по флагу mono.
        XCTAssertEqual(FontCatalog.category(family: "Papyrus", mono: false), .hand)
        XCTAssertEqual(FontCatalog.category(family: "SF Mono", mono: false), .mono)
        XCTAssertEqual(FontCatalog.category(family: "Fira Code", mono: true), .mono)
        XCTAssertEqual(FontCatalog.category(family: "Fira Code", mono: false), .sans)
    }

    // MARK: - Workflow и сводки (план WF9)

    func testWorkflowPayloadMatchesContract() throws {
        // Побайтно, контракт п. 3 плана WF9: id, action, at, scope, title, text.
        let body = CommandChannel.payload(action: "workflow",
                                          fields: ClaudeActions.workflowFields(title: "Vkusnoff",
                                                                               text: "Работаем\nдальше"),
                                          id: "1756900000123-0042",
                                          at: Date(timeIntervalSince1970: 1_756_900_000))
        XCTAssertEqual(body, "{\"id\":\"1756900000123-0042\",\"action\":\"workflow\","
            + "\"at\":\"2025-09-03T11:46:40Z\",\"scope\":\"window\",\"title\":\"Vkusnoff\","
            + "\"text\":\"Работаем\\u000aдальше\"}")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertEqual(json["text"] as? String, "Работаем\nдальше")
        XCTAssertEqual(json["scope"] as? String, "window")
        // Без доверия Accessibility заголовка нет — страница поймёт это как «окно в фокусе».
        XCTAssertTrue(CommandChannel.payload(action: "workflow",
                                             fields: ClaudeActions.workflowFields(title: "", text: "x"),
                                             id: "1-0001", at: Date(timeIntervalSince1970: 0))
            .hasSuffix("\"scope\":\"window\",\"title\":\"\",\"text\":\"x\"}"))
    }

    // MARK: - новое окно (план WF13)

    func testNewWindowPayloadMatchesContract() throws {
        // Побайтно, контракт п. 1 плана WF13, расширенный решением 1 плана WF16:
        // id, action, at, scope, title, x, y, text, folder, name, затем слои — тема, шрифт,
        // размер, рамка. `folder` и `name` есть всегда, пустая строка = «не трогать».
        let violet = catalog()[0]
        let body = CommandChannel.payload(
            action: ClaudeCommand.newWindow.rawValue,
            fields: ClaudeActions.newWindowFields(title: "Vkusnoff", x: 586, y: 303,
                                                  text: "PimpMyClaude 2",
                                                  folder: "/Users/dev/Projects/PimpMyClaude",
                                                  name: "PimpMyClaude 2",
                                                  theme: .set(violet), font: .keep,
                                                  size: .set(Size(answer: 16)), frame: .set(true)),
            id: "1756900000123-0042", at: Date(timeIntervalSince1970: 1_756_900_000))
        XCTAssertEqual(body, "{\"id\":\"1756900000123-0042\",\"action\":\"new-window\","
            + "\"at\":\"2025-09-03T11:46:40Z\",\"scope\":\"window\",\"title\":\"Vkusnoff\","
            + "\"x\":586,\"y\":303,\"text\":\"PimpMyClaude 2\","
            + "\"folder\":\"/Users/dev/Projects/PimpMyClaude\",\"name\":\"PimpMyClaude 2\","
            + "\"theme\":{\"id\":\"violet\",\"name\":\"Фиолетовая\",\"type\":\"dark\","
            + "\"palette\":{\"accent\":\"#a78bfa\",\"background\":\"#1b1626\",\"foreground\":\"#ece9f5\","
            + "\"sidebar\":\"#151021\",\"panel\":\"#241d33\",\"muted\":\"#8b81a6\"}},"
            + "\"size\":{\"answer\":16},\"frame\":true}")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertEqual(json["scope"] as? String, "window")
        XCTAssertEqual(json["folder"] as? String, "/Users/dev/Projects/PimpMyClaude")
        // Имя чата приходит на страницу ГОТОВЫМ, с номером: сайдбар на совпадения она не
        // проверяет — номер считает приложение по всем сессиям (критик В4).
        XCTAssertEqual(json["name"] as? String, "PimpMyClaude 2")
        XCTAssertEqual(json["text"] as? String, "PimpMyClaude 2")
        XCTAssertNil(json["font"], "слоя, который не трогаем, в команде нет вовсе")
        // Координаты — числа, а не строки: страница проверяет их Number.isFinite.
        XCTAssertEqual(json["x"] as? Int, 586)
        XCTAssertEqual(json["y"] as? Int, 303)
        XCTAssertNil(json["x"] as? String)

        // «Здесь же» (и хоткей ⌥⌘N) — поведение WF13 до буквы: папки и имени нет, слоёв нет,
        // первое сообщение одной строкой. Сам текст здесь не проверяется (он живёт в
        // `MenuModel.newWindowText`, #5767) — проверяется ПОРЯДОК полей.
        XCTAssertFalse(MenuModel.newWindowText.isEmpty)
        XCTAssertEqual(CommandChannel.payload(
            action: ClaudeCommand.newWindow.rawValue,
            fields: ClaudeActions.newWindowFields(title: "", x: 120, y: 120,
                                                  text: ClaudeAXTests.fixtureFirstMessage),
            id: "1-0001", at: Date(timeIntervalSince1970: 0)),
                       "{\"id\":\"1-0001\",\"action\":\"new-window\",\"at\":\"1970-01-01T00:00:00Z\","
                       + "\"scope\":\"window\",\"title\":\"\",\"x\":120,\"y\":120,\"text\":\"Привет\","
                       + "\"folder\":\"\",\"name\":\"\"}")
        // Сброс слоя уходит как null — правило слоёв то же, что у команды `theme`.
        XCTAssertTrue(CommandChannel.payload(
            action: ClaudeCommand.newWindow.rawValue,
            fields: ClaudeActions.newWindowFields(title: "", x: 0, y: 0, text: "Проект",
                                                  folder: "/tmp/Проект", name: "Проект",
                                                  theme: .reset, frame: .reset),
            id: "1-0001", at: Date(timeIntervalSince1970: 0))
            .hasSuffix("\"folder\":\"/tmp/Проект\",\"name\":\"Проект\",\"theme\":null,\"frame\":null}"))

        // Адресация ГЛАВНОМУ окну (дополнение 05.09 к плану WF19): `match` стоит сразу за
        // title, как у команды `theme`; поля нет — команда прежняя до байта.
        XCTAssertEqual(CommandChannel.payload(
            action: ClaudeCommand.newWindow.rawValue,
            fields: ClaudeActions.newWindowFields(title: "Claude", match: "/epitaxy/local_f44e46bb",
                                                  x: 120, y: 120, text: "Привет"),
            id: "1-0001", at: Date(timeIntervalSince1970: 0)),
                       "{\"id\":\"1-0001\",\"action\":\"new-window\",\"at\":\"1970-01-01T00:00:00Z\","
                       + "\"scope\":\"window\",\"title\":\"Claude\",\"match\":\"/epitaxy/local_f44e46bb\","
                       + "\"x\":120,\"y\":120,\"text\":\"Привет\",\"folder\":\"\",\"name\":\"\"}")

        // Чем красить новое окно (вопрос 2 макета WF16, ответ Элвиса «1»): вид проекта, а пока
        // его нет — вид окна, из которого нажали.
        let project = ProjectSettings(theme: .set(violet))
        let window = ProjectSettings(size: .set(Size(answer: 16)))
        XCTAssertEqual(ClaudeActions.newWindowLayers(project: project, window: window).theme.value?.id,
                       "violet")
        XCTAssertTrue(ClaudeActions.newWindowLayers(project: project, window: window).size.isKeep,
                      "вид проекта берётся целиком, а не смешивается с окном")
        XCTAssertEqual(ClaudeActions.newWindowLayers(project: nil, window: window).size.value,
                       Size(answer: 16))
        // Файл проекта есть, а слоёв в нём нет — это не «не красить», а «как у окна».
        XCTAssertEqual(ClaudeActions.newWindowLayers(project: ProjectSettings(name: "Проект"),
                                                     window: window).size.value, Size(answer: 16))
        XCTAssertTrue(ClaudeActions.newWindowLayers(project: nil, window: ProjectSettings()).isEmpty)

        // Авто-цвет проекта в команде (план WF36 п. 4): файла у папки нет — окно рождается
        // цветом ПАПКИ, а не соседнего чата, и не ждёт, пока до него доберётся ProjectPaint.
        let auto = AutoPaint.projectTheme(folderName: "Dictator")
        let byName = ClaudeActions.newWindowLayers(project: nil, window: window, autoColor: auto)
        XCTAssertEqual(byName.theme.value?.id, auto.id)
        XCTAssertEqual(byName.size.value, Size(answer: 16), "остальные слои — от окна-источника")
        // Тему окна-источника авто-цвет перебивает: иначе окно откроется чужим цветом
        // и перекрасится через такты.
        let painted = ProjectSettings(theme: .set(violet), size: .set(Size(answer: 16)))
        XCTAssertEqual(ClaudeActions.newWindowLayers(project: nil, window: painted,
                                                     autoColor: auto).theme.value?.id, auto.id)
        // Свой вид проекта сильнее авто-цвета — он и есть выбор Элвиса.
        XCTAssertEqual(ClaudeActions.newWindowLayers(project: project, window: window,
                                                     autoColor: auto).theme.value?.id, "violet")
        // Тумблер «🗂 Цвет по проекту» выключен (или задан вид «всем окнам») — авто-цвета нет
        // вовсе, и всё ведёт себя ровно как до WF36.
        XCTAssertEqual(ClaudeActions.newWindowLayers(project: nil, window: painted,
                                                     autoColor: nil).theme.value?.id, "violet")
    }

    // MARK: - «Обкэшить» из попапа (план WF37, часть B1, задачи #5575 и #5535)

    /// Эталоны контракта лежат в репозитории: `tests/fixtures/cashout/`, путь — от `Repo.root`,
    /// как у канала «Пимп». Их читают ОБА батча волны, и байты у них одни на двоих.
    private static func cashoutFixture(_ name: String) throws -> String {
        try String(contentsOf: Repo.root
            .appendingPathComponent("tests/fixtures/cashout/\(name)"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let cashoutID = "1756900000123-0042"
    private static let cashoutAt = Date(timeIntervalSince1970: 1_756_900_000)
    private static let cashoutMainMatch = "/epitaxy/local_facfb20c-4b3c-4aa9-838f-e084b0941b74"
    private static let cashoutPopoutChat = "local_4dae798d-aed9-42d7-bd1b-3631eb360c07"
    /// Первое сообщение, записанное В ЭТАЛОНАХ (`tests/fixtures/cashout/new-window-transfer*`):
    /// эталон держит ПОРЯДОК полей команды, и трогать его файлы ради смены текста не надо.
    /// Сам текст живёт в `MenuModel.newWindowText` и проверяется отдельно (#5767,
    /// `testNewWindowFirstMessageAsksToWait`).
    private static let fixtureFirstMessage = "Привет"

    /// Резолвер окна стенда (в бою — `WindowIdentity.resolveNative` по номеру окна от лоадера):
    /// заголовки из `main` — главное окно, из `chats` — попап своего чата, прочее — не опознано.
    static func resolver(main: Set<String> = [], chats: [String: String] = [:], popouts: Set<String> = [],
                         at: Date = Date(timeIntervalSince1970: 0)) -> (String, CGRect?) -> WindowIdentity {
        return { title, _ in
            if main.contains(title) { return .page(ChatPage(kind: .main, chat: nil, title: title, store: "ok", at: at)) }
            if let chat = chats[title] {
                return .page(ChatPage(kind: .popout, chat: chat, title: title, store: "ok", at: at))
            }
            if popouts.contains(title) { return .page(ChatPage(kind: .popout, chat: nil, title: title, store: "ok", at: at)) }
            return .unknown
        }
    }

    private func routeActions() -> ClaudeActions {
        ClaudeActions(app: IsolatedClaudeApp.make(), commands: CommandChannel(), themes: [], fonts: [])
    }

    /// Главное окно с ОТКРЫТЫМ названным чатом носит имя чата, а не заглушку «Claude»
    /// (критик, блокер 3): различает их только резолвер окна, и развилка верит ему одному.
    func testCashoutRouteMainByResolver() {
        let actions = routeActions()
        actions.windowIdentity = ClaudeAXTests.resolver(main: ["PimpMyClaude"])
        actions.isMainWindowTitle = { _ in false } // заголовок резолвер не перебивает
        XCTAssertEqual(actions.windowRoute(title: "PimpMyClaude", frame: nil), .main)
        // Запасное правило заголовка (меню, раскладки): заглушка и пустой заголовок — главное окно.
        XCTAssertTrue(ClaudeActions.isMainWindowTitle("Claude"))
        XCTAssertTrue(ClaudeActions.isMainWindowTitle("  "))
        XCTAssertFalse(ClaudeActions.isMainWindowTitle("VkusnoffKz 2"))
    }

    /// Окно не опознано или попап не назвал свой чат — адресовать нечем, и действие молчит
    /// (заглушку «Claude» носит и безымянный попап, #5534; до WF116 такое окно шло заголовком).
    func testCashoutRouteUnknownOrNamelessPopoutIsNil() {
        let actions = routeActions()
        actions.windowIdentity = ClaudeAXTests.resolver(popouts: ["Claude"])
        XCTAssertNil(actions.windowRoute(title: "Claude", frame: nil))
        XCTAssertNil(actions.windowRoute(title: "VkusnoffKz 2", frame: nil))
        XCTAssertNil(routeActions().windowRoute(title: "Claude", frame: nil), "резолвера нет — окно неизвестно")
    }

    /// Попап назвал свой чат в круге probe — команда уходит полем `chat`, и заголовок
    /// страница не смотрит вовсе (переименование чата адрес больше не сбивает, #5455).
    func testCashoutRoutePopoutKnownChat() {
        let actions = routeActions()
        actions.windowIdentity = ClaudeAXTests.resolver(chats: ["VkusnoffKz 2": ClaudeAXTests.cashoutPopoutChat])
        XCTAssertEqual(actions.windowRoute(title: "VkusnoffKz 2", frame: nil),
                       .popout(chat: ClaudeAXTests.cashoutPopoutChat))
    }

    /// Задача #5715: выбор цвета/шрифта/размера в меню адресуется той же развилкой, что
    /// «Обкэшить», — главному окну путь, вынесенному чату его id. Без адреса команда уходила
    /// ВСЕМ окнам с таким же именем чата (главное окно «Claude» и безымянный попап).
    func testThemeCommandAddressesOneWindow() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudeax-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let actions = actionsOnDisk(dir: dir, now: { Date(timeIntervalSince1970: 1_757_000_000) })
        actions.windowIdentity = ClaudeAXTests.resolver(main: ["PimpMyClaude"],
                                                        chats: ["VkusnoffKz 2": ClaudeAXTests.cashoutPopoutChat])
        actions.mainWindowMatch = { ClaudeAXTests.cashoutMainMatch }
        let window = MenuModel.themeScopeWindow

        // Главное окно — путь страницы, и поля `chat` у него нет никогда.
        let main = actions.themeAddress(scope: window, title: "PimpMyClaude")
        XCTAssertEqual(main.match, ClaudeAXTests.cashoutMainMatch)
        XCTAssertNil(main.chat)
        // Попап назвал свой чат в круге probe — адрес по чату, и пути ему не шлём.
        let popout = actions.themeAddress(scope: window, title: "VkusnoffKz 2")
        XCTAssertNil(popout.match)
        XCTAssertEqual(popout.chat, ClaudeAXTests.cashoutPopoutChat)
        // Окно не опознано — адреса нет, и команда ждёт опознания (`whenIdentified`).
        let guest = actions.themeAddress(scope: window, title: "Гость")
        XCTAssertNil(guest.match)
        XCTAssertNil(guest.chat)
        XCTAssertFalse(guest.valid)
        // План WF77 (#6734): заголовок носят два окна — адрес выбирает резолвер окна (в бою —
        // номер окна от лоадера), и без рамки это ничья.
        let left = CGRect(x: -792, y: -842, width: 496, height: 838)
        let right = CGRect(x: -290, y: -842, width: 496, height: 838)
        let named = actions.windowIdentity
        actions.windowIdentity = { title, frame in
            guard title == "Ожидание задачи" else { return named(title, frame) }
            guard let frame = frame else { return .ambiguous }
            return .page(ChatPage(kind: .popout, chat: frame.minX == left.minX ? "local_left" : "local_right",
                                  title: title, store: "ok", at: Date(timeIntervalSince1970: 0)))
        }
        XCTAssertEqual(actions.themeAddress(scope: window, title: "Ожидание задачи",
                                            frame: left).chat, "local_left")
        XCTAssertEqual(actions.themeAddress(scope: window, title: "Ожидание задачи",
                                            frame: right).chat, "local_right")
        XCTAssertNil(actions.themeAddress(scope: window, title: "Ожидание задачи").chat,
                     "рамки нет — ничья, адреса нет")
        actions.windowIdentity = named
        // «Всем окнам» адреса не имеет вовсе, пустой заголовок значит «окно в фокусе».
        XCTAssertNil(actions.themeAddress(scope: MenuModel.themeScopeAll,
                                          title: "PimpMyClaude").match)
        XCTAssertNil(actions.themeAddress(scope: window, title: "").match)

        // Байты команды: порядок полей scope, title, match?, chat? — тот же, что у «Обкэшить».
        let fields = ClaudeActions.themeFields(scope: window, title: "VkusnoffKz 2",
                                               match: popout.match, chat: popout.chat,
                                               theme: .keep, font: .keep)
        let body = CommandChannel.payload(action: "theme", fields: fields,
                                          id: ClaudeAXTests.cashoutID, at: ClaudeAXTests.cashoutAt)
        XCTAssertFalse(body.contains("\"match\""))
        XCTAssertTrue(body.contains("\"chat\":\"\(ClaudeAXTests.cashoutPopoutChat)\""), body)
    }

    /// Побайтно с эталоном: главное окно — scope, title, match.
    func testCashoutPayloadMain() throws {
        let body = CommandChannel.payload(
            action: ClaudeCommand.cashout.rawValue,
            fields: ClaudeActions.cashoutFields(title: "PimpMyClaude",
                                                match: ClaudeAXTests.cashoutMainMatch),
            id: ClaudeAXTests.cashoutID, at: ClaudeAXTests.cashoutAt)
        XCTAssertEqual(body, try ClaudeAXTests.cashoutFixture("cashout-main.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertEqual(json["scope"] as? String, "window")
        XCTAssertNil(json["chat"], "главному окну поле chat не шлётся никогда")
    }

    /// На домашнем экране пути у главного окна нет — адрес прежний, заголовком (риск 7 плана).
    func testCashoutPayloadMainHome() throws {
        XCTAssertEqual(CommandChannel.payload(
            action: ClaudeCommand.cashout.rawValue,
            fields: ClaudeActions.cashoutFields(title: "Claude", match: ChatProbe.homePath),
            id: ClaudeAXTests.cashoutID, at: ClaudeAXTests.cashoutAt),
                       try ClaudeAXTests.cashoutFixture("cashout-main-home.json"))
    }

    /// Побайтно с эталоном: попап — scope, title, chat; id чата неизвестен — только заголовок,
    /// и `match` попапу не уходит ни в том, ни в другом случае.
    func testCashoutPayloadPopoutChat() throws {
        let body = CommandChannel.payload(
            action: ClaudeCommand.cashout.rawValue,
            fields: ClaudeActions.cashoutFields(title: "VkusnoffKz 2",
                                                chat: ClaudeAXTests.cashoutPopoutChat),
            id: ClaudeAXTests.cashoutID, at: ClaudeAXTests.cashoutAt)
        XCTAssertEqual(body, try ClaudeAXTests.cashoutFixture("cashout-popout.json"))
        XCTAssertFalse(body.contains("\"match\""), "попапу путь главного окна не шлётся никогда")
        XCTAssertEqual(CommandChannel.payload(
            action: ClaudeCommand.cashout.rawValue,
            fields: ClaudeActions.cashoutFields(title: "VkusnoffKz 2"),
            id: ClaudeAXTests.cashoutID, at: ClaudeAXTests.cashoutAt),
                       try ClaudeAXTests.cashoutFixture("cashout-popout-title.json"))
    }

    /// Контракт `new-window` с переносом (критик, блокер 2): `transfer:true` стоит ПОСЛЕ
    /// `name` и ПЕРЕД слоями. Побайтно с эталонами — их же читает батч страницы.
    func testNewWindowPayloadWithTransfer() throws {
        let violet = catalog()[0]
        XCTAssertEqual(CommandChannel.payload(
            action: ClaudeCommand.newWindow.rawValue,
            fields: ClaudeActions.newWindowFields(title: "VkusnoffKz 2",
                                                  match: ClaudeAXTests.cashoutMainMatch,
                                                  x: 586, y: 303, text: ClaudeAXTests.fixtureFirstMessage,
                                                  folder: "/Users/dev/Projects/VkusnoffKz",
                                                  name: "VkusnoffKz 3", transfer: true,
                                                  theme: .set(violet),
                                                  size: .set(Size(answer: 16)), frame: .set(true)),
            id: ClaudeAXTests.cashoutID, at: ClaudeAXTests.cashoutAt),
                       try ClaudeAXTests.cashoutFixture("new-window-transfer.json"))
        // Проекта нет («Здесь же») — папка и имя пустые, а перенос всё равно нужен.
        XCTAssertEqual(CommandChannel.payload(
            action: ClaudeCommand.newWindow.rawValue,
            fields: ClaudeActions.newWindowFields(title: "VkusnoffKz 2",
                                                  match: ClaudeAXTests.cashoutMainMatch,
                                                  x: 586, y: 303, text: ClaudeAXTests.fixtureFirstMessage,
                                                  transfer: true),
            id: ClaudeAXTests.cashoutID, at: ClaudeAXTests.cashoutAt),
                       try ClaudeAXTests.cashoutFixture("new-window-transfer-plain.json"))
    }

    /// Сторож: поле ставит ТОЛЬКО ветка «Обкэшить». ⌥⌘N, «▸ проект», «Здесь же» и канал
    /// «Пимп» шлют прежний контракт WF16 — тот же байт в байт, но без `transfer`.
    func testNewWindowPayloadWithoutTransferUnchanged() throws {
        let plain = CommandChannel.payload(
            action: ClaudeCommand.newWindow.rawValue,
            fields: ClaudeActions.newWindowFields(title: "VkusnoffKz 2",
                                                  match: ClaudeAXTests.cashoutMainMatch,
                                                  x: 586, y: 303,
                                                  text: ClaudeAXTests.fixtureFirstMessage),
            id: ClaudeAXTests.cashoutID, at: ClaudeAXTests.cashoutAt)
        XCTAssertFalse(plain.contains("\"transfer\""))
        XCTAssertEqual(plain, try ClaudeAXTests.cashoutFixture("new-window-transfer-plain.json")
            .replacingOccurrences(of: ",\"transfer\":true", with: ""))
        // И у команды со слоями поля нет тоже — иначе перенос уехал бы в чужое окно.
        let violet = catalog()[0]
        XCTAssertFalse(CommandChannel.payload(
            action: ClaudeCommand.newWindow.rawValue,
            fields: ClaudeActions.newWindowFields(title: "", x: 0, y: 0, text: "Проект",
                                                  folder: "/tmp/Проект", name: "Проект",
                                                  theme: .set(violet)),
            id: "1-0001", at: Date(timeIntervalSince1970: 0)).contains("transfer"))
    }

    // MARK: - «Обкэшить» заменяет окно (#5768, слово Элвиса 08.09 11:40)

    /// Новое окно рождается РОВНО в углу донора: ни уступа в 40 pt, ни обрезки по главному
    /// экрану — иначе окно уезжало и на соседнее место, и на другой монитор.
    func testCashoutOriginTakesDonorCorner() {
        let donor = CGRect(x: 1200.4, y: 340.6, width: 700, height: 900)
        XCTAssertEqual(ClaudeActions.cashoutOrigin(donor: donor).x, 1200)
        XCTAssertEqual(ClaudeActions.cashoutOrigin(donor: donor).y, 341)
        // Точка «Нового окна» на том же окне — с уступом: у замены его быть не должно.
        XCTAssertNotEqual(ClaudeActions.cashoutOrigin(donor: donor).x,
                          ClaudeActions.popoutOrigin(near: donor, area: nil).x)
        // Окно на втором мониторе (отрицательный x) остаётся на нём.
        XCTAssertEqual(ClaudeActions.cashoutOrigin(donor: CGRect(x: -900, y: 100,
                                                                 width: 500, height: 800)).x, -900)
        // Рамки донора нет (AX молчит) — прежняя точка от угла экрана, замены не будет.
        XCTAssertEqual(ClaudeActions.cashoutOrigin(donor: nil).x, ClaudeActions.popoutWindowFallback.x)
        XCTAssertEqual(ClaudeActions.cashoutOrigin(donor: nil).y, ClaudeActions.popoutWindowFallback.y)
    }

    /// Страница ещё ничего не сказала — ждём; сказала «вставлено» — закрываем; сказала
    /// приговор — не закрываем ничего и говорим причину (#5779). Отказ СОСЕДНЕЙ страницы
    /// («перенос не в это окно») работу не заканчивает.
    func testCashoutWaitsForDeliveryNotForWindow() {
        let at = Date(timeIntervalSince1970: 1_757_000_000)
        func page(_ title: String, _ said: String?) -> ChatPage {
            ChatPage(kind: .popout, chat: nil, title: title, store: "ok", cashout: said, at: at)
        }
        // Окно уже родилось и даже ответило — но пока не «вставлено», это ожидание.
        XCTAssertEqual(ClaudeActions.cashoutDelivery(pages: [page("VkusnoffKz 3", nil)]), .waiting)
        XCTAssertEqual(ClaudeActions.cashoutDelivery(pages: [page("VkusnoffKz 3", "ждём"),
                                                             page("PimpMyClaude", "")]),
                       .waiting)
        // Доезд подтверждён — и заголовок берётся у той страницы, которая это сказала.
        XCTAssertEqual(ClaudeActions.cashoutDelivery(pages: [page("Гость", "ждём"),
                                                             page("VkusnoffKz 3", "вставлено")]),
                       .landed(title: "VkusnoffKz 3"))
        // Приговор с причиной: доезда не будет. «Вставлено» сильнее приговора соседней страницы.
        XCTAssertEqual(ClaudeActions.cashoutDelivery(pages: [page("Гость", "отказ: поле ввода пропало")]),
                       .refused("поле ввода пропало"))
        XCTAssertEqual(ClaudeActions.cashoutDelivery(pages: [page("Гость", "отказ: текст не попал в поле"),
                                                             page("VkusnoffKz 3", "вставлено")]),
                       .landed(title: "VkusnoffKz 3"))
        // Приговор без причины всё равно называет что-то человеческое, а не пустоту.
        XCTAssertEqual(ClaudeActions.cashoutDelivery(pages: [page("Гость", "отказ:")]),
                       .refused(MenuModel.cashoutNoAnswerReason))
        XCTAssertEqual(ClaudeActions.cashoutLanded, "вставлено")
        // Круг, пришедший ДО нажатия, говорит о прошлом переносе — его не слушаем вовсе
        // (находка гейта WF50): два «Обкэшить» подряд закрывали бы второго донора по
        // ответу про первый.
        XCTAssertEqual(ClaudeActions.cashoutDelivery(pages: [page("VkusnoffKz 3", "вставлено")],
                                                     since: at.addingTimeInterval(1)),
                       .waiting)
        XCTAssertEqual(ClaudeActions.cashoutDelivery(pages: [page("VkusnoffKz 3", "вставлено")],
                                                     since: at),
                       .landed(title: "VkusnoffKz 3"))
    }

    /// Потолок ожидания — СУММА пауз худшего честного хода цепочки, а не «на глаз» (#5785):
    /// фокус, очередь канала, опрос командного файла, ⌘N, сторож цепочки на странице,
    /// вставка с подтверждением и круг probe.
    func testCashoutWaitCoversWholeChain() {
        let focus = 0.1, queue = CommandChannel.minInterval, loader = 0.5, key = 0.8
        let pageGuard = 110.0         // NEW_WINDOW_GUARD_MS в inject.js (95 → 110 с К2 WF84)
        // Сторож вставки 0,3 с + ожидание чужого черновика 1,8 с + два способа вставки
        // с подтверждением (12 и 20 повторов по 150 мс).
        let paste = 0.3 + 1.8 + 12 * 0.15 + 20 * 0.15
        let probe = ChatProbe.cashoutInterval + 2 + 1 + 2 // пол частоты, лоадер, обход, тик
        let honest = focus + queue + loader + key + pageGuard + paste + probe
        XCTAssertGreaterThanOrEqual(ClaudeActions.cashoutWaitSeconds, honest,
                                    "потолок меньше суммы пауз — Элвис получит «не доехало» раньше доезда")
        XCTAssertEqual(ClaudeActions.cashoutWaitSeconds, 135)
        // Прежние 40 с не покрывали даже сторожа самой цепочки.
        XCTAssertLessThan(40, honest)
    }

    /// Наше окно — только то, чей заголовок назвала страница-адресат, и только среди окон,
    /// которых до ⌘N не было. Чужое окно тех же секунд (канал «Пимп», вынос другого чата,
    /// служебные окна Electron без заголовка) не занимает рамку и не закрывает донора.
    func testCashoutFreshWindowIsOnlyOurs() {
        let before: Set<CGWindowID> = [7, 9]
        let windows: [(id: CGWindowID, title: String)] = [
            (7, "VkusnoffKz 2"), (9, "PimpMyClaude"), (12, "VkusnoffKz 3"), (13, ""),
        ]
        XCTAssertEqual(ClaudeActions.cashoutFresh(title: "VkusnoffKz 3", before: before,
                                                  windows: windows), 12)
        // Окно с этим именем было и до ⌘N — оно не наше.
        XCTAssertNil(ClaudeActions.cashoutFresh(title: "VkusnoffKz 2", before: before,
                                                windows: windows))
        // Служебное окно без заголовка и пустое имя адресата рамку не занимают.
        XCTAssertNil(ClaudeActions.cashoutFresh(title: "", before: before, windows: windows))
        // Два свежих окна с одним именем — не угадываем вовсе.
        XCTAssertNil(ClaudeActions.cashoutFresh(title: "VkusnoffKz 3", before: before,
                                                windows: windows + [(14, "VkusnoffKz 3")]))
        // Заголовок ещё не доехал до AX — ждём, а не берём единственное свежее окно.
        XCTAssertNil(ClaudeActions.cashoutFresh(title: "VkusnoffKz 3", before: before,
                                                windows: [(7, "VkusnoffKz 2"), (12, "Claude")]))
    }

    /// Донора закрываем только после подтверждённого доезда, и только если он ещё на экране:
    /// не доехало — не закрываем ничего.
    func testCashoutClosesDonorOnlyAfterReplacement() {
        XCTAssertTrue(ClaudeActions.cashoutCloses(donor: 7, fresh: 12, onScreen: [7, 9, 12]))
        // Элвис закрыл старое окно сам, пока шла работа.
        XCTAssertFalse(ClaudeActions.cashoutCloses(donor: 7, fresh: 12, onScreen: [9, 12]))
        // «Новым» оказался сам донор — закрывать его значит закрыть то, что только что открыли.
        XCTAssertFalse(ClaudeActions.cashoutCloses(donor: 7, fresh: 7, onScreen: [7, 9]))
    }

    /// Плашка говорит правду (#5779, задача 3): «старое закрыл» — только когда `AX.close`
    /// правда сработал; у окна без кнопки закрытия текст другой. И у каждого отказа своя
    /// причина: молчаливый выход = «кнопка не работает» (урок ElvisOS).
    func testCashoutNoticesTellTheTruth() {
        XCTAssertTrue(MenuModel.cashoutReplacedNotice.contains("Старое закрыл"))
        XCTAssertTrue(MenuModel.cashoutCloseFailedNotice.contains("закрыть не смог"))
        XCTAssertFalse(MenuModel.cashoutCloseFailedNotice.contains("Старое закрыл"))
        XCTAssertEqual(MenuModel.cashoutKeptNotice("перенос протух"),
                       "Перенос не доехал (перенос протух) — старое окно оставил как было")
        XCTAssertTrue(MenuModel.cashoutKeptNotice(MenuModel.cashoutNoAnswerReason)
                        .contains("не подтвердила вставку"))
        XCTAssertTrue(MenuModel.cashoutNoWindowNotice.contains("оставил как было"))
    }

    /// Без карты probe (канал занят агентом, тумблер выключен) ответов нет — и донор не
    /// закрывается НИКОГДА: это и есть безопасная деградация. Плюс пауза между рамкой и
    /// закрытием — урок ElvisOS о свежем окне (#5784).
    func testCashoutWithoutAnswersNeverCloses() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudeax-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let actions = actionsOnDisk(dir: dir, now: { Date(timeIntervalSince1970: 1_757_000_000) })
        XCTAssertEqual(ClaudeActions.cashoutDelivery(pages: actions.cashoutAnswers()), .waiting)
        XCTAssertFalse(actions.cashoutPending, "работы нет — тик не должен трогать окна")
        // Тик без работы молчит: ни плашек, ни движения окон.
        var warnings: [String] = []
        actions.onWarning = { warnings.append($0) }
        actions.cashoutTick()
        XCTAssertTrue(warnings.isEmpty)
        XCTAssertEqual(ClaudeActions.cashoutSettlePause, 0.35)
        XCTAssertEqual(ClaudeActions.axWindowTimeout, 1.0)
    }

    /// Канал probe спрашивает о доезде ТОЛЬКО пока идёт перенос: `status()` считается на
    /// каждой из четырёх десятков страниц, и платить за него в обычном круге незачем (#5779).
    func testChatProbeScriptAsksAboutCashoutOnlyWhenNeeded() {
        let plain = ChatProbe.script(nonce: "chats-1-0001", scan: false, cash: false)
        let asking = ChatProbe.script(nonce: "chats-1-0001", scan: false, cash: true)
        XCTAssertFalse(plain.contains("cashout"))
        XCTAssertFalse(plain.contains("api.status"))
        XCTAssertTrue(asking.contains("api.status()"))
        XCTAssertTrue(asking.contains("cashout"))
        // Все четыре варианта скрипта остаются НАШИМИ: иначе приложение уступило бы канал
        // самому себе и замолчало на минуту.
        for scan in [false, true] {
            for cash in [false, true] {
                XCTAssertTrue(ChatProbe.isOwnScript(ChatProbe.script(nonce: "chats-1-0002",
                                                                     scan: scan, cash: cash)))
            }
        }
        XCTAssertFalse(ChatProbe.isOwnScript("\(ChatProbe.mark) chats-1-0002\nчужое"))

        // Обычный круг остался ПОБАЙТНО прежним: иначе первый запуск после обновления
        // приложения считал бы свой же вчерашний probe.js чужим и молчал 10 минут.
        XCTAssertEqual(plain, """
        \(ChatProbe.mark) chats-1-0001
        // Пишет PimpMyClaude: спрашивает у страницы, какой в ней чат (план WF29).
        // Свой probe.js на гейте? Приложение уступит: чужой свежий файл оно не переписывает.
        (function () {
          try {
            var api = window.__myclaude;
            if (!api || typeof api.chats !== "function") return {v:1,nonce:"chats-1-0001",kind:"other",store:"skip"};
            return api.chats({ scan: false, nonce: "chats-1-0001" });
          } catch (e) {
            return {v:1,nonce:"chats-1-0001",kind:"other",store:"skip"};
          }
        })()

        """)
    }

    /// Слово о доезде приезжает тем же кругом probe, что и чаты: `status().cashout.delivery`.
    /// Чужая строка просеивается, как папка: не строка, пустая или огромная — считаем, что
    /// страница промолчала, и донор не закрывается.
    func testChatProbeReadsCashoutResult() {
        XCTAssertEqual(ChatProbe.cashoutWord(["delivery": " вставлено "]), "вставлено")
        XCTAssertNil(ChatProbe.cashoutWord(nil))
        XCTAssertNil(ChatProbe.cashoutWord(["delivery": ""]))
        XCTAssertNil(ChatProbe.cashoutWord(["record": true]))
        XCTAssertNil(ChatProbe.cashoutWord("вставлено"))
        XCTAssertNil(ChatProbe.cashoutWord(["delivery": String(repeating: "я", count: 201)]))

        let json = """
        {"at":"2026-09-08T13:00:00.000Z","results":[
          {"id":1,"url":"about:blank","source":{"loader":8,"origin":"https://claude.ai","url":"about:blank","processId":1,"routingId":1},"result":{"v":1,"nonce":"chats-1-0003","kind":"popout",
           "title":"VkusnoffKz 3","store":"ok",
           "cashout":{"record":false,"to":null,"title":null,"stampedAt":null,"refusal":null,
                      "delivery":"вставлено"}}}]}
        """
        let pages = ChatProbe.parse(json.data(using: .utf8), nonce: "chats-1-0003",
                                    at: Date(timeIntervalSince1970: 1_757_000_000))
        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages.first?.cashout, "вставлено")
        XCTAssertEqual(ClaudeActions.cashoutDelivery(pages: pages), .landed(title: "VkusnoffKz 3"))
    }

    /// Пока идёт перенос, канал probe работает при ЛЮБОМ тумблере: по ответу страницы
    /// закрывается окно Элвиса с его текстом, и молчать тут нельзя (#5779).
    func testChatProbeWorksWhileCashoutPending() {
        var script: String?
        var writes = 0
        var now = Date(timeIntervalSince1970: 1_757_100_000)
        let files = ChatProbeFiles(scriptInfo: { script == nil ? nil : ("\(writes)", now) },
                                   readScript: { script },
                                   writeScript: { text in
                                       script = text
                                       writes += 1
                                       return true
                                   },
                                   resultInfo: { nil }, readResult: { nil })
        let probe = ChatProbe(files: files, now: { now }, random: { 7 })
        var pending = false
        probe.isEnabled = { false }
        probe.isCashoutPending = { pending }

        probe.tick(windowTitles: ["VkusnoffKz 2"], indexRevision: 1)
        XCTAssertEqual(writes, 0, "тумблер выключен и переноса нет — канала не касаемся")

        pending = true
        probe.tick(windowTitles: ["VkusnoffKz 2"], indexRevision: 1)
        XCTAssertEqual(writes, 1)
        XCTAssertTrue(script?.contains("cashout") == true, "круг обязан спросить о доезде")
        // Свой пол частоты: прежние 15 с — это 15 с лишнего окна на экране.
        XCTAssertEqual(ChatProbe.cashoutInterval, 4)
        XCTAssertLessThan(ChatProbe.cashoutInterval, ChatProbe.askInterval)

        now = now.addingTimeInterval(60)
        pending = false
        probe.tick(windowTitles: ["VkusnoffKz 2"], indexRevision: 1)
        XCTAssertEqual(writes, 1, "перенос кончился — канал снова молчит по тумблеру")
    }

    // MARK: - «Новый чат», ⌘N и первое сообщение (#5734, #5735, #5767)

    /// Задача #5734: «💬 Новый чат» из вынесенного окна больше не жмёт ⌘N — его исполняет
    /// главное окно, и разговор Элвиса там сменялся новым чатом. Из главного окна всё как
    /// было; попап с #7749 заменяется новым чатом — `Fix7749Tests`.
    func testNewChatFromMainWindowPressesKey() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudeax-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("command.json")
        let actions = actionsOnDisk(dir: dir, now: { Date(timeIntervalSince1970: 1_757_000_000) })
        actions.windowIdentity = ClaudeAXTests.resolver(main: ["PimpMyClaude"],
                                                        chats: ["VkusnoffKz 2": ClaudeAXTests.cashoutPopoutChat])
        actions.mainWindowMatch = { ClaudeAXTests.cashoutMainMatch }
        var delays: [TimeInterval] = []
        actions.schedule = { delay, _ in delays.append(delay) }

        // Главное окно: команд в канал не уходит вовсе, только ⌘N (он отложен на focusDelay).
        actions.newChatCommand(nil, title: "PimpMyClaude")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path),
                       "главному окну «Новый чат» команд не шлёт — как было до #5734")
        XCTAssertEqual(delays, [actions.focusDelay])
        // Заголовка окна нет в карте probe — окно неизвестное: ни ⌘N, ни команд.
        XCTAssertNil(actions.windowRoute(title: "Гость", frame: nil))
    }

    /// Задача #5735: ⌘N жмётся от МОМЕНТА ЗАПИСИ файла, а не от клика. Команда простояла в
    /// очереди канала — клавиша ждёт её, иначе главное окно уезжало на пустой `/epitaxy`
    /// раньше, чем страница получала команду, и вернуть его на чат Элвиса было некому.
    func testNewWindowPressesKeyAfterCommandLandsOnDisk() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudeax-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("command.json")
        var now = Date(timeIntervalSince1970: 1_757_000_000)
        // Таймер канала ловим сами: так видно, что команда правда стоит в очереди.
        var queued: [(wait: TimeInterval, run: () -> Void)] = []
        let channel = CommandChannel(path: file, now: { now },
                                     schedule: { wait, block in queued.append((wait, block)) })
        let actions = ClaudeActions(app: IsolatedClaudeApp.make(), commands: channel, themes: [], fonts: [],
                                    themeStore: ThemeStore(defaults: MemoryThemeDefaults()),
                                    myThemes: MyThemesStore(url: dir.appendingPathComponent("my.json")))
        actions.clock = { now }
        actions.mainWindowMatch = { nil }
        var delays: [TimeInterval] = []
        // Пауза фокуса — шаг живого AX: на Маке, где Claude запущен и доступ выдан,
        // `perform` находит окно в фокусе и шлёт команду после неё (#6667 — тест считал,
        // что в прогоне живого AX не бывает). Её прокручиваем сами, ⌘N ждём отдельно.
        var focusSteps: [() -> Void] = []
        actions.schedule = { delay, block in
            if delay == actions.focusDelay { focusSteps.append(block) } else { delays.append(delay) }
        }

        // Перед «Новым окном» в канал уже написали (примерка темы, цвет проекта, сводка).
        actions.perform(.scroll, on: nil)
        XCTAssertEqual(try ClaudeAXTests.action(of: file), "scroll")

        actions.perform(.newWindow, on: nil)
        focusSteps.forEach { $0() }
        XCTAssertEqual(try ClaudeAXTests.action(of: file), "scroll",
                       "команда стоит в очереди — зазор канала ещё не вышел")
        XCTAssertTrue(delays.isEmpty, "⌘N нельзя жать раньше, чем команда легла на диск")

        // Очередь дошла до записи — только теперь отсчитываются 0,8 с до ⌘N.
        now = now.addingTimeInterval(CommandChannel.minInterval)
        XCTAssertEqual(queued.count, 1)
        // Через `XCTUnwrap`, а не `removeFirst()`: на пустой очереди падал ВЕСЬ прогон
        // (#6667) — четыре класса тестов после этой строки не исполнялись вовсе.
        try XCTUnwrap(queued.first).run()
        queued.removeFirst()
        XCTAssertEqual(try ClaudeAXTests.action(of: file), ClaudeCommand.newWindow.rawValue)
        XCTAssertEqual(delays, [actions.newWindowKeyDelay])
    }

    /// Задача #5767 (она же половина #5447): первое сообщение нового окна больше не запускает
    /// работу — оно прямо просит ничего не делать и не читать правила, потому что полная
    /// ориентировка агента стоила по 2–5 долларов на окно. Имя чата от этого не зависит:
    /// оно уходит своим полем `name`, и текст у окна с папкой ровно тот же.
    func testNewWindowFirstMessageAsksToWait() throws {
        let text = MenuModel.newWindowText.lowercased()
        XCTAssertTrue(text.contains("не читай правила"), MenuModel.newWindowText)
        XCTAssertTrue(text.contains("ничего не делай"), MenuModel.newWindowText)
        XCTAssertFalse(MenuModel.newWindowText.contains("/"), "путей в первом сообщении быть не должно")

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudeax-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("command.json")
        let actions = actionsOnDisk(dir: dir, now: { Date(timeIntervalSince1970: 1_757_000_000) })
        actions.mainWindowMatch = { nil }
        actions.chatName = { project in "\(project.name) 2" }
        // Как в тесте очереди (#6667): пауза фокуса живого AX прокручивается здесь же,
        // а отложенный ⌘N остаётся невыполненным — жать клавишу в прогоне незачем.
        var focusSteps: [() -> Void] = []
        actions.schedule = { delay, block in if delay == actions.focusDelay { focusSteps.append(block) } }
        actions.newWindow(in: ClaudeAXTests.project("PimpMyClaude"), on: nil)
        focusSteps.forEach { $0() }

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: try Data(contentsOf: file))
                                    as? [String: Any])
        XCTAssertEqual(json["name"] as? String, "PimpMyClaude 2", "имя чата осталось на месте")
        XCTAssertEqual(json["text"] as? String, MenuModel.newWindowText,
                       "с папкой первое сообщение больше не имя проекта — оно стоило хода модели")
    }

    private static func action(of file: URL) throws -> String {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: try Data(contentsOf: file))
                                    as? [String: Any])
        return try XCTUnwrap(json["action"] as? String)
    }

    // MARK: - авто-Allow (#5736)

    /// Запрос страницы «открой HTML в Chrome» (#6618): только GET /open-html, абсолютный путь, страница.
    func testHtmlChromeRequestParsing() {
        let ok = HtmlChromeOpener.parse("GET /open-html?mode=auto&path=%2FUsers%2Fe%2F%D0%BE%D1%82%D1%87%D1%91%D1%82%20a.html HTTP/1.1\r\nHost: x\r\n")
        XCTAssertNil(ok)
        XCTAssertEqual(HtmlChromeOpener.parse("GET /open-html?path=%2Fa.HTM HTTP/1.1")?.mode, .click)
        XCTAssertNil(HtmlChromeOpener.parse("GET /open-html?path=%2Fetc%2Fpasswd HTTP/1.1"))
        XCTAssertEqual(HtmlChromeOpener.parse("GET /open-html?path=%2Fa%2Fb.PNG HTTP/1.1")?.path, "/a/b.PNG")
        XCTAssertEqual(HtmlChromeOpener.parse("GET /open-html?path=%2Fa%2Fb.pdf HTTP/1.1")?.path, "/a/b.pdf")
        XCTAssertNil(HtmlChromeOpener.parse("GET /open-html?path=%2Fa%2Fb.sh HTTP/1.1"))
        XCTAssertNil(HtmlChromeOpener.parse("GET /open-html?path=a.html HTTP/1.1"))
        XCTAssertNil(HtmlChromeOpener.parse("POST /open-html?path=%2Fa.html HTTP/1.1"))
        XCTAssertNil(HtmlChromeOpener.parse("GET /other?path=%2Fa.html HTTP/1.1"))
    }

    /// Explicit opening reuses, reloads and activates the existing browser tab.
    func testHtmlChromeScriptModes() {
        let click = HtmlChromeOpener.script(url: "file:///a.html")
        XCTAssertTrue(click.contains("set active tab index of w to i"))
        XCTAssertTrue(click.contains("reload t"))
        XCTAssertTrue(click.contains("set target to \"file:///a.html\""))
    }

    /// Сторож (критик В2 плана WF16 — повтор блокера Б1 из WF14): Carbon-хоткеи регистрируются перебором
    /// `Hotkeys.entries` (id = индекс+1), поэтому `.newWindow` обязан остаться в списке И на своём месте.
    func testNewWindowKeepsHotkeyEntry() throws {
        let index = try XCTUnwrap(Hotkeys.entries.firstIndex { $0.command == .newWindow })
        XCTAssertEqual(index, 2, "индекс .newWindow съехал — вместе с ним съедет id Carbon-хоткея")
        let entry = try XCTUnwrap(Hotkeys.entry(for: .newWindow))
        XCTAssertEqual(entry.registersHotkey, true, ".newWindow перестал регистрировать хоткей")
        XCTAssertEqual(entry.key?.keyCode, 0x2D)
        XCTAssertEqual(entry.key?.mods, [.command, .option])
    }

    /// Проект из индекса чатов: папка в ~/Projects, имя — её последний компонент.
    private static func project(_ name: String, at: Double = 3000) -> Project {
        Project(folder: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Projects", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true), name: name, lastFocusedAt: at)
    }

    func testPopoutWindowPayloadMatchesContract() throws {
        // Побайтно, решение Элвиса 04.09: те же поля без text.
        let body = CommandChannel.payload(
            action: ClaudeCommand.popoutWindow.rawValue,
            fields: ClaudeActions.popoutWindowFields(title: "Привет", x: 120, y: 120),
            id: "1-0001", at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(body, "{\"id\":\"1-0001\",\"action\":\"popout-window\","
            + "\"at\":\"1970-01-01T00:00:00Z\",\"scope\":\"window\",\"title\":\"Привет\","
            + "\"x\":120,\"y\":120}")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertNil(json["text"])
        XCTAssertEqual(json["x"] as? Int, 120)
        XCTAssertNil(json["match"], "поля match нет — адресация заголовком, как раньше")

        // Дополнение 05.09 к плану WF19: чат выносит ГЛАВНОЕ окно, на каком бы окне ни нажали, —
        // адресуем его путём страницы (с попапа команда уходила с его заголовком и молчала).
        XCTAssertEqual(CommandChannel.payload(
            action: ClaudeCommand.popoutWindow.rawValue,
            fields: ClaudeActions.popoutWindowFields(title: "Привет", match: "/epitaxy/local_f44e46bb",
                                                     x: 120, y: 120),
            id: "1-0001", at: Date(timeIntervalSince1970: 0)),
                       "{\"id\":\"1-0001\",\"action\":\"popout-window\","
                       + "\"at\":\"1970-01-01T00:00:00Z\",\"scope\":\"window\",\"title\":\"Привет\","
                       + "\"match\":\"/epitaxy/local_f44e46bb\",\"x\":120,\"y\":120}")

        // «↩︎ Вернуть эти чаты» (план WF41): `chat` и `name` идут ПОСЛЕ `y`, а адрес у команды
        // один — путь главного окна: поле `chat` для страницы значит «эта страница и есть тот
        // чат», и закрытый разговор такую команду не взял бы вовсе.
        XCTAssertEqual(CommandChannel.payload(
            action: ClaudeCommand.popoutWindow.rawValue,
            fields: ClaudeActions.popoutWindowFields(title: "", match: "/epitaxy/local_f44e46bb",
                                                     x: 294, y: 34, chat: "local_gone",
                                                     name: "Вкуснофф"),
            id: "1-0002", at: Date(timeIntervalSince1970: 0)),
                       "{\"id\":\"1-0002\",\"action\":\"popout-window\","
                       + "\"at\":\"1970-01-01T00:00:00Z\",\"scope\":\"window\",\"title\":\"\","
                       + "\"match\":\"/epitaxy/local_f44e46bb\",\"x\":294,\"y\":34,"
                       + "\"chat\":\"local_gone\",\"name\":\"Вкуснофф\"}")
        // Путь берётся из диагностики лоадера: одна страница claude.ai — она и есть главное окно,
        // ни одной или несколько — nil, и адресация остаётся прежней (живой ~/Library не трогаем).
        XCTAssertNil(ClaudeActions.mainWindowMatch(statusURL: URL(fileURLWithPath: "/нет/такого")))
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudeax-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let status = dir.appendingPathComponent(ProjectIndex.statusFileName)
        func write(_ urls: [String]) {
            let list = urls.map { "{\"url\":\"\($0)\"}" }.joined(separator: ",")
            XCTAssertTrue(CommandChannel.writeAtomic(status, "{\"webContents\":[\(list)]}"))
        }
        write(["https://claude.ai/epitaxy/local_f44e46bb", "about:blank"])
        XCTAssertEqual(ClaudeActions.mainWindowMatch(statusURL: status), "/epitaxy/local_f44e46bb")
        // Две страницы claude.ai — какая из них главная, отсюда не видно: молчим и адресуем
        // заголовком, как раньше.
        write(["https://claude.ai/epitaxy/local_f44e46bb", "https://claude.ai/epitaxy/local_aa11bb22"])
        XCTAssertNil(ClaudeActions.mainWindowMatch(statusURL: status))
        write(["about:blank"])
        XCTAssertNil(ClaudeActions.mainWindowMatch(statusURL: status))

        // Координаты — точки Quartz: угол окна под кнопкой + 40/40, обрезанные по экрану так,
        // чтобы окно 900×700 влезло целиком; окна нет — 120/120.
        let area = CGRect(x: 0, y: 25, width: 1440, height: 875)
        XCTAssertEqual(ClaudeActions.popoutOrigin(near: nil, area: area).x, 120)
        XCTAssertEqual(ClaudeActions.popoutOrigin(near: nil, area: area).y, 120)
        // На большом экране уступ ничем не обрезан.
        let wide = CGRect(x: 0, y: 25, width: 1920, height: 1175)
        let near = ClaudeActions.popoutOrigin(near: CGRect(x: 546, y: 263, width: 900, height: 700),
                                              area: wide)
        XCTAssertEqual(near.x, 586)
        XCTAssertEqual(near.y, 303)
        // Окно у правого нижнего угла — уступ уехал бы за экран.
        let corner = ClaudeActions.popoutOrigin(near: CGRect(x: 1000, y: 800, width: 400, height: 300),
                                                area: area)
        XCTAssertEqual(corner.x, 540) // 1440 − 900
        XCTAssertEqual(corner.y, 200) // 25 + 875 − 700
        // И за левый верхний край тоже не пускаем.
        let above = ClaudeActions.popoutOrigin(near: CGRect(x: -100, y: -100, width: 400, height: 300),
                                               area: area)
        XCTAssertEqual(above.x, 0)
        XCTAssertEqual(above.y, 25)
    }

    /// Новое окно рождается на экране ОКНА-ИСТОЧНИКА (#5731): `NSScreen.main` — это экран
    /// активного окна любого приложения, и с ним «🪟 Новое окно» и «Обкэшить» из попапа
    /// уезжали на второй монитор — та же болезнь, что чинили у «Расставить» 08.09.
    func testPopoutOriginStaysOnSourceWindowScreen() {
        let laptop = CGRect(x: 0, y: 34, width: 1470, height: 860)
        let external = CGRect(x: 1470, y: 0, width: 1920, height: 1080)
        let source = CGRect(x: 2000, y: 200, width: 900, height: 700)
        // Экран источника выбирает тот же `pick`, что и «Расставить».
        XCTAssertEqual(Screens.pick(screens: [laptop, external], for: [source]), 1)

        let right = ClaudeActions.popoutOrigin(near: source, area: external)
        XCTAssertEqual(right.x, 2040) // уступ 40/40 на своём экране ничем не обрезан
        XCTAssertEqual(right.y, 240)
        // По главному экрану ту же точку прижало бы к правому краю ноутбука — это и был #5731.
        let wrong = ClaudeActions.popoutOrigin(near: source, area: laptop)
        XCTAssertEqual(wrong.x, 570) // 1470 − 900
        XCTAssertLessThan(CGFloat(wrong.x), external.minX)

        // Без подсказки экран считается сам, а не берётся «как есть»: точка обрезана рабочей
        // областью того экрана, где стоит источник (на одном мониторе он единственный).
        if let area = Screens.usableFrame(holding: [source]) {
            let auto = ClaudeActions.popoutOrigin(near: source)
            XCTAssertGreaterThanOrEqual(CGFloat(auto.x), area.minX)
            XCTAssertLessThanOrEqual(CGFloat(auto.x),
                                     max(area.minX, area.maxX - ClaudeActions.popoutWindowSize.width))
        }
    }

    func testWorkflowKitLandsInApplicationSupport() throws {
        // Комплект из бандла (в тесте — из репозитория) ложится рядом с command.json.
        let source = Repo.root
            .appendingPathComponent("resources/workflow-kit", isDirectory: true)
        let target = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudeax-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: target) }
        XCTAssertTrue(WorkflowKit.install(from: source, to: target))
        for name in WorkflowKit.files {
            XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent(name)),
                           try Data(contentsOf: source.appendingPathComponent(name)), name)
        }
        // В поле ввода уходит кикофф из бандла, и он ссылается на разложенные правила.
        let kickoff = try XCTUnwrap(WorkflowKit.kickoff(directory: source))
        XCTAssertTrue(kickoff.contains(WorkflowKit.rulesName), kickoff)
        XCTAssertTrue(kickoff.contains("MyClaude/\(WorkflowKit.installedFolderName)"), kickoff)
        // Комплекта нет — ни падения, ни текста.
        XCTAssertFalse(WorkflowKit.install(from: nil, to: target))
        XCTAssertNil(WorkflowKit.kickoff(directory: URL(fileURLWithPath: "/nope/\(UUID().uuidString)")))
    }

    func testStatusPayloadMatchesContract() throws {
        // Побайтно, контракт п. 2 плана WF9: id, action, at, scope, projects[{name,text}].
        let projects = [StatusProject(name: "PimpMyClaude", text: "# ⚪PimpMyClaude\n1️⃣ Workflow ✅"),
                        StatusProject(name: "SkilZZZ", text: "# 🟣SkilZZZ")]
        let body = CommandChannel.payload(action: "status", fields: StatusFeed.fields(projects),
                                          id: "1-0001", at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(body, "{\"id\":\"1-0001\",\"action\":\"status\","
            + "\"at\":\"1970-01-01T00:00:00Z\",\"scope\":\"all\",\"projects\":["
            + "{\"name\":\"PimpMyClaude\",\"text\":\"# ⚪PimpMyClaude\\u000a1️⃣ Workflow ✅\"},"
            + "{\"name\":\"SkilZZZ\",\"text\":\"# 🟣SkilZZZ\"}]}")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertEqual(json["scope"] as? String, "all")
        let list = try XCTUnwrap(json["projects"] as? [[String: String]])
        XCTAssertEqual(list.map { $0["name"] }, ["PimpMyClaude", "SkilZZZ"])
        XCTAssertEqual(list.first?["text"], "# ⚪PimpMyClaude\n1️⃣ Workflow ✅")
        // Проектов нет — пустой список, а не сломанный JSON (такую команду StatusFeed не шлёт).
        XCTAssertEqual(CommandValue.array([]).json, "[]")
        // Содержимое не менялось — хэш тот же; поменялось хоть в одном проекте — другой.
        XCTAssertEqual(StatusFeed.digest(projects), StatusFeed.digest(projects))
        XCTAssertNotEqual(StatusFeed.digest(projects),
                          StatusFeed.digest([projects[0], StatusProject(name: "SkilZZZ", text: "!")]))

        // Общий потолок (критик п. 6; 128 КБ с WF202): проекты кладутся по порядку, хвост отбрасывается.
        let heavy = { (name: String) in
            StatusProject(name: name, text: String(repeating: "строка сводки\n", count: 500))
        }
        let many = (1...12).map { heavy("Проект \($0)") }
        let capped = StatusFeed.cap(many)
        XCTAssertLessThanOrEqual(StatusFeed.payloadSize(capped), StatusFeed.totalLimit)
        XCTAssertGreaterThan(capped.count, 0)
        XCTAssertLessThan(capped.count, many.count)
        XCTAssertEqual(capped.map { $0.name }, many.prefix(capped.count).map { $0.name })
        // Влезают все — не трогаем ни байта.
        XCTAssertEqual(StatusFeed.cap(projects), projects)
        // Не влез даже первый — режем ему текст, но проект остаётся.
        let alone = StatusFeed.cap([heavy("Один")], limit: 500)
        XCTAssertEqual(alone.count, 1)
        XCTAssertLessThanOrEqual(StatusFeed.payloadSize(alone), 500)
        XCTAssertTrue(heavy("Один").text.hasPrefix(alone[0].text))
    }

    func testStatusScanReadsProjectSummaries() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudeax-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func put(_ project: String, _ folder: String, _ text: String, at moment: Date = Date()) throws {
            let dir = root.appendingPathComponent(project).appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(StatusFeed.statusFileName)
            try Data(text.utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: moment], ofItemAtPath: url.path)
        }
        try put("PimpMyClaude", "docs", "# ⚪PimpMyClaude", at: now)
        try put("PimpMyClaude", "work", "не эта", at: now)        // docs идёт первым
        try put("Audited", "audit", "# аудит", at: now.addingTimeInterval(-3600))
        try put("Empty", "docs", "   \n", at: now)                 // пустая сводка не едет
        try FileManager.default.createDirectory(at: root.appendingPathComponent("NoStatus/src"),
                                                withIntermediateDirectories: true)

        let projects = StatusFeed.scan(root: root)
        // Свежие первыми (WF22): алфавит («Audited») уступает времени правки status.md.
        XCTAssertEqual(projects.map { $0.name }, ["PimpMyClaude", "Audited"])
        XCTAssertEqual(projects.first?.text, "# ⚪PimpMyClaude")
        // Папки проектов нет — ничего не читаем.
        XCTAssertTrue(StatusFeed.scan(root: root.appendingPathComponent("нет")).isEmpty)

        // projectsRoot из claude.json; ключа/файла нет — ~/Projects (WF108).
        let config = root.appendingPathComponent("claude.json")
        try Data("{\"minWindowWidth\":360,\"projectsRoot\":\"~/Projects\"}".utf8).write(to: config)
        XCTAssertEqual(StatusFeed.projectsRoot(configURL: config).path,
                       NSString(string: "~/Projects").expandingTildeInPath)
        try Data("{\"minWindowWidth\":360}".utf8).write(to: config)
        XCTAssertEqual(StatusFeed.projectsRoot(configURL: config).path,
                       NSString(string: StatusFeed.defaultProjectsRoot).expandingTildeInPath)
        XCTAssertEqual(StatusFeed.projectsRoot(configURL: root.appendingPathComponent("нет.json")).path,
                       NSString(string: StatusFeed.defaultProjectsRoot).expandingTildeInPath)
    }

    func testStatusSliceCutsOnWorkflowBlocks() {
        let head = "# ⚪PimpMyClaude\nобновлено 01:55\n"
        let block = { (index: Int) in "\(index)️⃣ Workflow ✅ готово\n" + String(repeating: "- строка сводки\n", count: 40) }
        let text = head + (1...9).map(block).joined()
        XCTAssertGreaterThan(text.utf8.count, StatusFeed.limit)

        let slice = StatusFeed.slice(text)
        XCTAssertLessThanOrEqual(slice.utf8.count, StatusFeed.limit)
        XCTAssertTrue(slice.hasPrefix(head), slice)
        // Режем с НАЧАЛА (WF22): шапка остаётся, из блоков едут ПОСЛЕДНИЕ и целыми.
        XCTAssertTrue(slice.hasSuffix("- строка сводки\n"), String(slice.suffix(40)))
        let kept = (1...9).filter { slice.contains("\($0)️⃣ Workflow") }
        XCTAssertGreaterThan(kept.count, 1)
        XCTAssertEqual(kept, Array((10 - kept.count)...9)) // хвост подряд, без дыр
        XCTAssertFalse(slice.contains("1️⃣ Workflow"), slice) // голова отрезана

        // Влезает целиком — не трогаем ни байта.
        XCTAssertEqual(StatusFeed.slice(head + block(1)), head + block(1))
        // Ни один блок не влез — режем по знакам, UTF-8 не рвём.
        let single = StatusFeed.slice(head + block(1), limit: 20)
        XCTAssertLessThanOrEqual(single.utf8.count, 20)
        XCTAssertTrue(head.hasPrefix(single), single)
        XCTAssertTrue(StatusFeed.isWorkflowHeading("1️⃣ Workflow ✅ готово"))
        XCTAssertTrue(StatusFeed.isWorkflowHeading("🔟 Workflow"))
        XCTAssertFalse(StatusFeed.isWorkflowHeading("1. Workflow"))
        XCTAssertFalse(StatusFeed.isWorkflowHeading("- строка сводки"))
        XCTAssertFalse(StatusFeed.isWorkflowHeading(""))
    }

    func testStatusFeedCompactKeepsHeadAndBlocks() {
        let text = """
        # ⚪PimpMyClaude
        обновлено 19:40

        4 воркфлоу
        2 готово
        3,5 ч потрачено

        1️⃣ Workflow ✅ готово
        - о чём: одна строка простыми словами
        - шаги 2 из 2
        - 00:17 → 01:20 · 1 ч
        - планирование · я · Fable high
        - проверка · 🔴 **Fable max**

        2️⃣ Workflow 💭 идёт
        - о чём: полоска
        - шаги 1 из 3
        - 13:05 → закончит примерно в 13:50 · идёт 25 мин
        - кодинг · 2 агента · Opus max 💭

        Сейчас: идёт кодинг.
        Ждёт Элвиса: буква по макету.
        """
        // Шапка целиком (с WF84 в её конце хвост «Сейчас:»/«Ждёт Элвиса:»), заголовки блоков
        // и четыре вида строк — остальное за бортом.
        XCTAssertEqual(StatusFeed.compact(text).components(separatedBy: "\n"), [
            "# ⚪PimpMyClaude",
            "обновлено 19:40",
            "4 воркфлоу",
            "2 готово",
            "3,5 ч потрачено",
            "Сейчас: идёт кодинг.",
            "Ждёт Элвиса: буква по макету.",
            "1️⃣ Workflow ✅ готово",
            "- о чём: одна строка простыми словами",
            "- шаги 2 из 2",
            "- 00:17 → 01:20 · 1 ч",
            "- планирование · я · Fable high",
            "- проверка · 🔴 **Fable max**",
            "2️⃣ Workflow 💭 идёт",
            "- о чём: полоска",
            "- шаги 1 из 3",
            "- 13:05 → закончит примерно в 13:50 · идёт 25 мин",
            "- кодинг · 2 агента · Opus max 💭",
        ])
        XCTAssertLessThan(StatusFeed.compact(text).utf8.count, text.utf8.count)
        // Посторонний пункт блока не едет, а шапка остаётся любой строкой.
        XCTAssertEqual(StatusFeed.compact("# ⚪Проект\nпримечание\n1️⃣ Workflow\n- план: docs/plan.md\n- шаги 1 из 2"),
                       "# ⚪Проект\nпримечание\n1️⃣ Workflow\n- шаги 1 из 2")
        // Сжатие идемпотентно: сжатую сводку можно сжать ещё раз без потерь.
        XCTAssertEqual(StatusFeed.compact(StatusFeed.compact(text)), StatusFeed.compact(text))
        XCTAssertTrue(StatusFeed.tailKind("Ждёт Элвиса: буква") != nil)
        XCTAssertTrue(StatusFeed.startsWithClock("13:05 → 13:50"))
        XCTAssertFalse(StatusFeed.startsWithClock("шаги 1 из 3"))
    }

    /// Идущий блок стоит в середине файла, а после него много запланированных (настоящий
    /// docs/status.md 07.09: 💭 на 22-м из 41): срез с начала обязан оставить его всё равно.
    func testStatusFeedKeepsRunningBlockCutFromStart() {
        func keys(_ number: Int) -> String { String(number).map { "\($0)\u{FE0F}\u{20E3}" }.joined() }
        func block(_ index: Int) -> String {
            let state = index == 22 ? "💭 идёт" : (index < 22 ? "✅ готово" : "⬜ запланирован")
            return "\(keys(index)) Workflow \(state)\n"
                + "- о чём: строка про воркфлоу номер \(index)\n"
                + "- шаги 1 из 3\n"
                + String(repeating: "- кодинг · 2 агента · Opus max\n", count: 6)
        }
        let head = "# ⚪PimpMyClaude\nобновлено 22:40\n41 воркфлоу\n"
        let text = head + (1...41).map(block).joined()
        XCTAssertGreaterThan(text.utf8.count, StatusFeed.limit)
        let slice = StatusFeed.slice(text)
        XCTAssertLessThanOrEqual(slice.utf8.count, StatusFeed.limit)
        XCTAssertTrue(slice.hasPrefix(head))
        XCTAssertTrue(slice.contains("\(keys(22)) Workflow 💭 идёт"), "идущий блок отрезан")
        XCTAssertTrue(slice.contains(block(22)), "идущий блок доехал не целым")
        let kept = slice.components(separatedBy: "\n").filter { StatusFeed.isWorkflowHeading($0) }
        XCTAssertEqual(kept.first.map { $0.hasPrefix(keys(22)) }, true, "живой блок первым после шапки")
        XCTAssertTrue(kept.last?.hasPrefix(keys(41)) == true, "хвост файла на месте")
        // Порядок — как в файле, без дыр внутри хвоста.
        let numbers = kept.compactMap { line in (1...41).first { line.hasPrefix(keys($0) + " Workflow") } }
        XCTAssertEqual(numbers, numbers.sorted())
        XCTAssertEqual(Array(numbers.dropFirst()), Array((41 - numbers.count + 2)...41))
    }

    func testStatusFeedCutsFromStart() {
        func keys(_ number: Int) -> String { String(number).map { "\($0)\u{FE0F}\u{20E3}" }.joined() }
        func block(_ index: Int) -> String {
            let state = index == 40 ? "💭 идёт" : "✅ готово"
            return "\(keys(index)) Workflow \(state)\n"
                + "- о чём: строка про воркфлоу номер \(index)\n"
                + "- шаги 2 из 2\n"
                + "- 00:17 → 01:20 · 1 ч\n"
                + String(repeating: "- кодинг · 2 агента · Opus max\n", count: 6)
        }
        let head = "# ⚪PimpMyClaude\nобновлено 19:40\n40 воркфлоу\n"
        let text = head + (1...40).map(block).joined()
        XCTAssertGreaterThan(text.utf8.count, StatusFeed.limit)

        let slice = StatusFeed.slice(text)
        XCTAssertLessThanOrEqual(slice.utf8.count, StatusFeed.limit)
        // Шапка на месте, а из блоков доехали последние — идущий 40-й в том числе.
        XCTAssertTrue(slice.hasPrefix(head), String(slice.prefix(80)))
        XCTAssertTrue(slice.contains("\(keys(40)) Workflow 💭 идёт"), String(slice.suffix(200)))
        let kept = slice.components(separatedBy: "\n").filter { StatusFeed.isWorkflowHeading($0) }
        XCTAssertGreaterThan(kept.count, 1)
        XCTAssertLessThan(kept.count, 40) // голова файла отрезана
        let all = (1...40).map { "\(keys($0)) Workflow " + ($0 == 40 ? "💭 идёт" : "✅ готово") }
        XCTAssertEqual(kept, Array(all.suffix(kept.count))) // ровно хвост, без дыр
        // Блок доезжает целым: у последнего заголовка все его строки на месте.
        XCTAssertTrue(slice.hasSuffix(block(40)), String(slice.suffix(60)))
    }

    func testStatusFeedOrderByMtime() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudeax-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func put(_ project: String, _ folder: String, _ text: String, minutesAgo: Double) throws {
            let dir = root.appendingPathComponent(project).appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(StatusFeed.statusFileName)
            try Data(text.utf8).write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(-minutesAgo * 60)], ofItemAtPath: url.path)
        }
        try put("Старый", "docs", "# 🟣Старый", minutesAgo: 90)
        try put("Свежий", "docs", "# ⚪Свежий", minutesAgo: 1)
        try put("Средний", "audit", "# 🟠Средний", minutesAgo: 30)
        // Свежие первыми — иначе 32 КБ достаются голове алфавита, а живой проект отваливается.
        XCTAssertEqual(StatusFeed.scan(root: root).map { $0.name }, ["Свежий", "Средний", "Старый"])
        // Одинаковое время — по имени: порядок не пляшет от обхода каталога.
        try put("Бета", "docs", "# 🟢Бета", minutesAgo: 1)
        try put("Альфа", "docs", "# 🔵Альфа", minutesAgo: 1)
        XCTAssertEqual(StatusFeed.scan(root: root).map { $0.name },
                       ["Альфа", "Бета", "Свежий", "Средний", "Старый"])
    }

    func testStatusFeedDigestOrderIndependent() {
        let pimp = StatusProject(name: "PimpMyClaude", text: "# ⚪PimpMyClaude\n1️⃣ Workflow ✅")
        let skil = StatusProject(name: "SkilZZZ", text: "# 💤SkilZZZ")
        // Порядок пляшет от «потрогали файл» — та же сводка не должна ехать заново.
        XCTAssertEqual(StatusFeed.digest([pimp, skil]), StatusFeed.digest([skil, pimp]))
        // Содержимое поменялось — хэш другой.
        XCTAssertNotEqual(StatusFeed.digest([pimp, skil]),
                          StatusFeed.digest([pimp, StatusProject(name: "SkilZZZ", text: "!")]))
        // Проект пропал или добавился — тоже другой.
        XCTAssertNotEqual(StatusFeed.digest([pimp, skil]), StatusFeed.digest([pimp]))
    }

    func testStatusFeedTotalLimitStillHolds() {
        XCTAssertEqual(StatusFeed.limit, 6 * 1024)
        XCTAssertEqual(StatusFeed.totalLimit, 128 * 1024, "WF202: столько принимает страница (STATUS_MAX_TOTAL)")
        let heavy = { (name: String) in
            StatusProject(name: name,
                          text: String(repeating: "- кодинг · 2 агента · Opus max\n", count: 200))
        }
        let many = (1...20).map { heavy("Проект \($0)") }
        let capped = StatusFeed.cap(many)
        XCTAssertLessThanOrEqual(StatusFeed.payloadSize(capped), StatusFeed.totalLimit)
        XCTAssertGreaterThan(capped.count, 0)
        XCTAssertLessThan(capped.count, many.count)
        // Отбрасывается хвост списка — свежие проекты идут первыми и доезжают.
        XCTAssertEqual(capped.map { $0.name }, many.prefix(capped.count).map { $0.name })
        // Влезают все — не трогаем ни байта.
        XCTAssertEqual(StatusFeed.cap(Array(many.prefix(2))), Array(many.prefix(2)))
    }

    // MARK: - мои темы

    /// `knobs` в `my-themes.json` (WF237: файл только читается — редактора и «Сохранить тему» нет): файл без них
    /// (и с мусором в них) разбор не роняет (критик В4), ручки чужой темы подбираются по палитре.
    func testThemeKnobsReadFromFile() throws {
        // Файл правит и сам Элвис: старый формат без knobs, мусор вместо объекта и половина
        // ключей — всё это просто «ручек нет», а не потерянный список.
        let hand = MyThemesStore.parse(Data("""
        {"version":1,"themes":[{"id":"user-1","name":"Старая","palette":{"accent":"#fff"}},
        {"id":"user-2","name":"Мусор","palette":{"accent":"#fff"},"knobs":"да"},
        {"id":"user-3","name":"Половина","palette":{"accent":"#fff"},"knobs":{"hue":10}},
        {"id":"user-4","name":"Годная","type":"light","palette":{"accent":"#fff"},
        "knobs":{"hue":10,"accent":5,"strength":40,"light":true}}]}
        """.utf8))
        XCTAssertEqual(hand.map { $0.id }, ["user-1", "user-2", "user-3", "user-4"])
        XCTAssertEqual(hand.map { $0.knobs == nil }, [true, true, true, false])
        XCTAssertEqual(hand.last?.knobs, ThemeKnobs(hue: 10, accent: 5, strength: 40, light: true))
        // Границы читаются с тем же зажимом, что и у ручек.
        XCTAssertEqual(MyThemesStore.parse(Data("""
        {"version":1,"themes":[{"id":"user-9","name":"Края","palette":{"accent":"#fff"},
        "knobs":{"hue":400,"accent":900,"strength":900,"light":false}}]}
        """.utf8)).first?.knobs, ThemeKnobs(hue: 40, accent: 180, strength: 100))

        // Ручки чужой темы восстанавливаются приблизительно — тон ±2°, сила ±5 % (п. 4 плана).
        let back = ThemeKnobs.from(palette: AutoPaint.palette(hue: 137, light: false, strength: 0.7), type: "dark")
        XCTAssertEqual(Double(back.hue), 137, accuracy: 2)
        XCTAssertEqual(Double(back.accent), 0, accuracy: 3)
        XCTAssertEqual(Double(back.strength), 70, accuracy: 6)
        XCTAssertFalse(back.light)
        XCTAssertTrue(ThemeKnobs.from(palette: catalog()[1].palette, type: "light").light)
        // Палитры нет вовсе — умолчания, а не падение.
        XCTAssertEqual(ThemeKnobs.from(palette: [:], type: "dark"),
                       ThemeKnobs(hue: ThemeKnobs.defaultHue, accent: 0,
                                  strength: ThemeKnobs.defaultStrength))
        // У своей темы ручки берутся из файла, а нет их — подбираются по палитре.
        XCTAssertEqual(ThemeKnobs.of(try XCTUnwrap(hand.last)),
                       ThemeKnobs(hue: 10, accent: 5, strength: 40, light: true))
        XCTAssertEqual(ThemeKnobs.of(myTheme()),
                       ThemeKnobs.from(palette: myTheme().palette, type: "dark"))
    }

    // MARK: - генератор палитр (план WF10; наборы «по кругу» сняты в WF237)

    /// Двенадцать hue по кругу — как раз то, что раскладывает «Радуга» на дюжине окон.
    private static let wheelHues: [Double] = (0..<12).map { Double($0) * 30 }

    func testAutoPaintPaletteIsValidAndReadable() throws {
        for light in [false, true] {
            for hue in ClaudeAXTests.wheelHues {
                // Крайние силы — «Пастель»/«Неон» и края «Монохрома».
                for strength in [0.0, 0.35, 0.5, 1.0] {
                    let where_ = "hue \(Int(hue))° \(light ? "светлая" : "тёмная") сила \(strength)"
                    let palette = AutoPaint.palette(hue: hue, light: light, strength: strength)
                    XCTAssertEqual(Set(palette.keys), Set(Theme.paletteOrder), where_)
                    for key in Theme.paletteOrder {
                        let hex = try XCTUnwrap(palette[key], where_)
                        XCTAssertNotNil(hex.range(of: "^#[0-9a-f]{6}$", options: .regularExpression),
                                        "\(where_): \(key) = \(hex)")
                    }
                    let background = try XCTUnwrap(palette["background"])
                    // Текст на фоне — AAA (≥ 7), приглушённый текст и акцент — AA (≥ 4,5).
                    let text = try XCTUnwrap(AutoPaint.contrast(hex: try XCTUnwrap(palette["foreground"]),
                                                                hex: background))
                    XCTAssertGreaterThanOrEqual(text, AutoPaint.textContrast, "\(where_): текст на фоне")
                    for key in ["muted", "accent"] {
                        let value = try XCTUnwrap(AutoPaint.contrast(hex: try XCTUnwrap(palette[key]),
                                                                     hex: background))
                        XCTAssertGreaterThanOrEqual(value, AutoPaint.accentContrast, "\(where_): \(key)")
                    }
                    // «Трендовые, не кричащие»: насыщенность фона ≤ 60 % (фикс-батч п. 2 — на
                    // 45 % выходило серо). Считаем её обратно из hex — по нему цвет и увидят.
                    let saturation = try XCTUnwrap(AutoPaint.saturation(hex: background))
                    XCTAssertLessThanOrEqual(saturation, AutoPaint.maxBackgroundSaturation, where_)
                    // Боковина темнее фона, панель светлее (у светлой темы — наоборот).
                    XCTAssertNotEqual(palette["sidebar"], background, where_)
                    XCTAssertNotEqual(palette["panel"], background, where_)
                }
            }
        }
    }

    func testAutoPaintAccentStaysInContrastBand() throws {
        // Акцент кладём в полосу контраста, а не в пол (фикс-батч п. 1): иначе жёлтый с зелёным
        // на тёмном фоне уходят за 10 и кричат, а синий с фиолетовым висят на 4,5 и тонут.
        // Проверка — весь круг с шагом 10°, в обоих режимах.
        for light in [false, true] {
            let mode = light ? "светлая" : "тёмная"
            let cap = AutoPaint.accentContrastCap(light: light)
            var luminances: [Double] = []
            for step in 0..<36 {
                let hue = Double(step) * 10
                let palette = AutoPaint.palette(hue: hue, light: light)
                let accent = try XCTUnwrap(palette["accent"])
                let value = try XCTUnwrap(AutoPaint.contrast(hex: accent,
                                                             hex: try XCTUnwrap(palette["background"])))
                XCTAssertGreaterThanOrEqual(value, AutoPaint.accentContrast, "\(mode) hue \(Int(hue))°")
                XCTAssertLessThanOrEqual(value, cap, "\(mode) hue \(Int(hue))°")
                let channels = try XCTUnwrap(AutoPaint.channels(hex: accent))
                luminances.append(AutoPaint.luminance(r: channels.r, g: channels.g, b: channels.b))
            }
            // Полоса держит и яркость: по кругу акцент разъезжается не больше чем вдвое —
            // иначе одно окно из четырёх било бы в глаза, а другое пряталось.
            let spread = try XCTUnwrap(luminances.max()) / max(try XCTUnwrap(luminances.min()), 0.0001)
            XCTAssertLessThanOrEqual(spread, 2, "\(mode): яркость акцента разъехалась в \(spread) раза")
        }
    }

    // MARK: - живой блок claude.css и merge claude.json (план WF14, решение 1)

    /// Блок контракта побайтно — тем же текстом он лежит в репозиторном claude-patch/claude.css.
    private static let expectedBlock = """
    /* PimpMyClaude:auto */
    #myclaude-window-frame{border-radius:15px !important}
    .epitaxy-titlebar span[class*="w-[var(--chat-gutter-start"]{width:32px !important}
    .tiles-shell{min-width:0 !important}
    [class*="--chat-column-gutter-start"]{--chat-column-gutter-start:5px !important;--chat-column-gutter-end:5px !important}
    [class*="ps-[var(--chat-gutter"],[class*="pe-[var(--chat-gutter"],.epitaxy-transcript-width,.epitaxy-composer-width{padding-inline-start:5px !important;padding-inline-end:5px !important;padding-left:5px !important;padding-right:5px !important}
    [class*="ps-[var(--chat"],[class*="pe-[var(--chat"]{padding-inline-start:5px !important;padding-inline-end:5px !important}
    /* /PimpMyClaude:auto */
    """

    func testLiveStyleBlockMatchesContract() throws {
        XCTAssertEqual(LiveStyle.block(padding: 5, radius: 15), ClaudeAXTests.expectedBlock)
        // Радиус — по версии macOS: у Tahoe (26+) угол ≈ 17 pt, у 13–15 — 10.
        XCTAssertEqual(LiveStyle.frameRadius(majorVersion: 26), 15)
        XCTAssertEqual(LiveStyle.frameRadius(majorVersion: 15), 10)
        // Необязательный ключ frameRadius в claude.json перебивает порог; мусор — нет.
        XCTAssertEqual(LiveStyle.frameRadius(config: "{\"frameRadius\":12}", majorVersion: 26), 12)
        XCTAssertEqual(LiveStyle.frameRadius(config: "{\"frameRadius\":999}", majorVersion: 26), 15)
        XCTAssertEqual(LiveStyle.frameRadius(config: "не json", majorVersion: 15), 10)
        XCTAssertEqual(LiveStyle.frameRadius(config: nil, majorVersion: 26), 15)
        // Ползунок зажат в 0…40 (#9148), умолчание — 24 (слово Элвиса 08.10).
        XCTAssertEqual(LiveStyle.clamp(-5), 0)
        XCTAssertEqual(LiveStyle.clamp(41), 40)
        XCTAssertEqual(LiveStyle.clamp(5), 5)
        XCTAssertEqual(LiveStyle.defaultSidePadding, 24)
        // Тот же блок лежит в репозиторном claude-patch/claude.css: свежая установка правильна
        // ещё до первого запуска приложения (критик В5).
        let repo = try String(contentsOf: Repo.root
            .appendingPathComponent("claude-patch").appendingPathComponent("claude.css"),
                              encoding: .utf8)
        XCTAssertTrue(repo.contains(LiveStyle.block(padding: LiveStyle.defaultSidePadding, radius: 15)), repo)
        XCTAssertTrue(repo.hasSuffix(LiveStyle.markerEnd + "\n"), repo)
        // Умолчание полей — то же и в репозиторном claude.json (мелочь М6: цифра в двух таргетах).
        let config = try String(contentsOf: Repo.root
            .appendingPathComponent("claude-patch").appendingPathComponent("claude.json"),
                                encoding: .utf8)
        XCTAssertEqual(LiveStyle.number(config, key: LiveStyle.sidePaddingKey),
                       LiveStyle.defaultSidePadding)
    }

    func testLiveStyleBlockKeepsForeignRules() throws {
        let block = LiveStyle.block(padding: 5, radius: 15)
        let old = LiveStyle.block(padding: 16, radius: 10)
        let mine = "/* Элвис */\n.a{color:red}\n"

        // 1. Маркеров нет — блок дописан в КОНЕЦ, чужое дословно цело.
        let appended = LiveStyle.applying(block: block, to: mine)
        XCTAssertEqual(appended, mine + block + "\n")
        // 2. Повторный вызов даёт байт-в-байт тот же файл (иначе mtime дёргается каждую секунду).
        XCTAssertEqual(LiveStyle.applying(block: block, to: appended), appended)
        // 3. Блок в СЕРЕДИНЕ файла — заменяется на месте, порядок строк не меняется.
        XCTAssertEqual(LiveStyle.applying(block: block, to: "/* до */\n" + old + "\n/* после */\n"),
                       "/* до */\n" + block + "\n/* после */\n")
        // 4. Блок дважды — мусор от первого маркера до последнего вырезан, свежий блок в конце.
        XCTAssertEqual(LiveStyle.applying(block: block, to: "/* до */\n" + old + "\n" + old + "\n/* после */\n"),
                       "/* до */\n/* после */\n" + block + "\n")
        // 5. Только один из маркеров — та же уборка.
        XCTAssertEqual(LiveStyle.applying(block: block, to: "/* до */\n" + LiveStyle.markerStart + "\n.b{color:blue}\n"),
                       "/* до */\n.b{color:blue}\n" + block + "\n")
        // 6. Файла нет и 7. файл пустой — в файле остаётся один блок.
        XCTAssertEqual(LiveStyle.applying(block: block, to: ""), block + "\n")
        XCTAssertEqual(LiveStyle.applying(block: block, to: "\n\n"), block + "\n")
        // 8. Файл без финального перевода строки — блок всё равно отдельными строками.
        XCTAssertEqual(LiveStyle.applying(block: block, to: "/* хвост */"),
                       "/* хвост */\n" + block + "\n")
    }

    func testLiveStyleWritesBlockAndConfigOnDisk() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudeax-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let css = dir.appendingPathComponent(LiveStyle.cssFileName)
        let config = dir.appendingPathComponent(LiveStyle.configFileName)
        // Живой claude.json Элвиса: minWindowWidth 300 (не 360 из репозитория) и projectsRoot.
        try Data("""
        {
          "minWindowWidth" : 300,
          "projectsRoot" : "/Users/dev/Projects",
          "sidePadding" : 16
        }

        """.utf8).write(to: config)
        try Data("/* Элвис */\n.a{color:red}\n".utf8).write(to: css)

        XCTAssertEqual(LiveStyle.currentSidePadding(directory: dir), 16)
        XCTAssertTrue(LiveStyle.writeBlock(padding: 5, directory: dir, majorVersion: 26))
        XCTAssertTrue(LiveStyle.writeConfig(sidePadding: 5, directory: dir))
        XCTAssertEqual(try String(contentsOf: css, encoding: .utf8),
                       "/* Элвис */\n.a{color:red}\n" + ClaudeAXTests.expectedBlock + "\n")
        XCTAssertEqual(LiveStyle.currentSidePadding(directory: dir), 5)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: try Data(contentsOf: config)) as? [String: Any])
        XCTAssertEqual(json["minWindowWidth"] as? Int, 300, "merge потерял ширину окна")
        XCTAssertEqual(json["projectsRoot"] as? String, "/Users/dev/Projects")
        XCTAssertEqual(json["sidePadding"] as? Int, 5)
        // Путь остаётся читаемым: без withoutEscapingSlashes вышло бы «\/Users\/elvis\/…».
        XCTAssertTrue(try String(contentsOf: config, encoding: .utf8)
            .contains("\"/Users/dev/Projects\""))

        // Повторный вызов с тем же значением записи НЕ делает — иначе лоадер каждую секунду
        // переставляет CSS во всех страницах.
        let past = Date(timeIntervalSince1970: 0)
        for url in [css, config] {
            try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: url.path)
        }
        XCTAssertTrue(LiveStyle.writeBlock(padding: 5, directory: dir, majorVersion: 26))
        XCTAssertTrue(LiveStyle.writeConfig(sidePadding: 5, directory: dir))
        for url in [css, config] {
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date,
                           past, "лишняя запись дёрнула mtime у \(url.lastPathComponent)")
        }

        // Битый claude.json не трогаем вовсе (критик В8), а claude.css при этом пишем.
        try Data("{сломано".utf8).write(to: config)
        XCTAssertFalse(LiveStyle.writeConfig(sidePadding: 8, directory: dir))
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), "{сломано")
        XCTAssertTrue(LiveStyle.writeBlock(padding: 8, directory: dir, majorVersion: 26))
        XCTAssertTrue(try String(contentsOf: css, encoding: .utf8).contains("border-radius:15px"))
        XCTAssertTrue(try String(contentsOf: css, encoding: .utf8).contains("--chat-column-gutter-start:8px"))

        // Файла claude.json нет — создаём из умолчаний, ничего не теряя.
        try FileManager.default.removeItem(at: config)
        XCTAssertTrue(LiveStyle.writeConfig(sidePadding: 99, directory: dir))
        let fresh = try XCTUnwrap(JSONSerialization.jsonObject(with: try Data(contentsOf: config)) as? [String: Any])
        XCTAssertEqual(fresh["sidePadding"] as? Int, LiveStyle.maxSidePadding) // зажали 99 → 40
        XCTAssertEqual(fresh["minWindowWidth"] as? Int, 280, "умолчание чистой установки — 280 (WF45)")
        XCTAssertTrue(try String(contentsOf: config, encoding: .utf8).hasSuffix("}\n"))

        // Пустой claude.json — как «настроек ещё нет»: пишем свой ключ и не падаем.
        XCTAssertNil(LiveStyle.merged(config: "{сломано", sidePadding: 5))
        XCTAssertEqual(LiveStyle.number(LiveStyle.merged(config: "", sidePadding: 7),
                                        key: LiveStyle.sidePaddingKey), 7)
        // Ключи по алфавиту (sortedKeys) — тот же порядок, что у Patcher.ensureConfig.
        let merged = try XCTUnwrap(LiveStyle.merged(config: "{\"projectsRoot\":\"/tmp\",\"minWindowWidth\":300}",
                                                    sidePadding: 5))
        XCTAssertLessThan(try XCTUnwrap(merged.range(of: "minWindowWidth")).lowerBound,
                          try XCTUnwrap(merged.range(of: "projectsRoot")).lowerBound)
    }

    // MARK: - живые цвета (план WF18; сняты в WF237 — разовое гашение)

    /// Лист 48, ответ 2.1: «Живые цвета» один раз выключатся у всех. Правило — как у гашения неона (`retireTick`):
    /// без окон Claude молчим, не чаще раза в 5 с и не больше трёх раз за поколение; ключи стираются после третьей
    /// отправки поколения, а Claude не запущен — ждут следующего.
    func testLiveColorsRetireOncePerGenerationThenForgets() {
        XCTAssertEqual(CommandValue.object(LiveColorsRetire.fields()).json, "{\"scope\":\"all\",\"on\":false}")
        XCTAssertEqual(LiveColorsRetire.action, "live-colors")
        let defaults = MemoryThemeDefaults()
        let retire = LiveColorsRetire(defaults: defaults)
        var sent = 0
        let send = { () -> Bool in sent += 1; return true }
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        // Не крутились — гасить нечего.
        XCTAssertFalse(retire.pending)
        XCTAssertFalse(retire.tick(titles: ["Vkusnoff"], at: start, send: send))

        for key in LiveColorsRetire.keys { defaults.set(300, forKey: key) }
        defaults.set(true, forKey: LiveColorsRetire.onKey)
        XCTAssertTrue(retire.pending)
        // Claude не на экране — молчим; канал не взял — попытка не тратится.
        XCTAssertFalse(retire.tick(titles: [], at: start, send: send))
        XCTAssertFalse(retire.tick(titles: ["Vkusnoff"], at: start) { false })
        XCTAssertTrue(retire.tick(titles: ["Vkusnoff"], at: start, send: send))
        XCTAssertFalse(retire.tick(titles: ["Vkusnoff"], at: start.addingTimeInterval(4), send: send), "раньше 5 с")
        XCTAssertTrue(retire.tick(titles: ["Vkusnoff"], at: start.addingTimeInterval(5), send: send))
        // Поколение сменилось до третьей отправки (Claude перезапустили) — ключи на месте, счёт заново.
        retire.beginGeneration()
        XCTAssertTrue(retire.pending)
        for step in 0..<3 {
            XCTAssertTrue(retire.tick(titles: ["Vkusnoff"], at: start.addingTimeInterval(10 + 5 * Double(step)),
                                      send: send))
        }
        XCTAssertEqual(sent, 5)
        // Третья отправка поколения — ключи стёрты, дальше тишина и в новых поколениях.
        XCTAssertFalse(retire.pending)
        XCTAssertTrue(LiveColorsRetire.keys.allSatisfy { defaults.object(forKey: $0) == nil })
        retire.beginGeneration()
        XCTAssertFalse(retire.tick(titles: ["Vkusnoff"], at: start.addingTimeInterval(60), send: send))
        XCTAssertEqual(sent, 5)
    }

    func testProjectPaintStaysSilentWhileLiveColorsRun() throws {
        // Блокер Б2 плана WF18: живой слой перекрывает цвет проекта — пока живые цвета
        // крутятся, ProjectPaint не шлёт ни одной команды. Выключили — красит как обычно.
        let box = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudeax-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: box) }
        let root = box.appendingPathComponent("Projects", isDirectory: true)
        let sessions = box.appendingPathComponent("sessions", isDirectory: true)
        let folder = root.appendingPathComponent("PimpMyClaude", isDirectory: true)
        let place = sessions.appendingPathComponent("4646c58f/8cb117af", isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(".git"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
        let session: [String: Any] = ["sessionId": "local_a1", "title": "Vkusnoff",
                                      "titleSource": "user", "cwd": folder.path,
                                      "originCwd": folder.path, "lastFocusedAt": 3000,
                                      "lastActivityAt": 3000, "isArchived": false]
        try JSONSerialization.data(withJSONObject: session)
            .write(to: place.appendingPathComponent("local_a1.json"))

        let index = ProjectIndex(sessionsDirectory: sessions,
                                 statusURL: box.appendingPathComponent("status.json"),
                                 projectsRoot: root, home: box)
        let store = ProjectSettingsStore(registryURL: box.appendingPathComponent("projects.json"))
        store.write(ProjectSettings(name: "PimpMyClaude", theme: .set(catalog()[0])), to: folder)
        let paint = ProjectPaint(index: index, store: store, defaults: MemoryThemeDefaults())
        var sent = 0
        var live = true
        paint.send = { _ in
            sent += 1
            return true
        }
        paint.windowTitles = { ["Vkusnoff"] }
        paint.isLiveColorsOn = { live }

        paint.tick()
        XCTAssertEqual(sent, 0, "цвет проекта заговорил поверх живых цветов")
        live = false
        // То же самое, но окном владеет панель «Своя тема» (решение 1.6 плана WF20): обычная
        // команда `theme` погасила бы примерку ползунка на странице.
        ClaudeActions.themeEditorTitle = "Vkusnoff"
        defer { ClaudeActions.themeEditorTitle = nil }
        paint.tick()
        XCTAssertEqual(sent, 0, "цвет проекта заговорил поверх открытой панели")
        // Панель закрыли — отпечаток не протух, окно красится ближайшим тиком.
        ClaudeActions.themeEditorTitle = nil
        paint.tick()
        XCTAssertEqual(sent, 1)
    }

    // MARK: - Сверки, которые до WF24 держались только на глазах

    /// Радиус рамки по версии macOS — через константы `LiveStyle`, а не через числа (решение 6.1 плана WF24):
    /// «26 → 15» гейт ещё может подвинуть, а «13–15 → 10» и есть автоматическая половина проверки
    /// на старых системах — своей машины с ними у нас нет.
    func testFrameRadiusMatchesMacOSMajor() throws {
        for major in [13, 14, 15] {
            XCTAssertEqual(LiveStyle.frameRadius(majorVersion: major), LiveStyle.legacyFrameRadius,
                           "macOS \(major): угол окна 10–11 pt, строке в claude.css там взяться неоткуда")
        }
        XCTAssertEqual(LiveStyle.legacyFrameRadius, 10)
        XCTAssertEqual(LiveStyle.frameRadius(majorVersion: LiveStyle.modernMacOSVersion - 1),
                       LiveStyle.legacyFrameRadius)
        XCTAssertEqual(LiveStyle.frameRadius(majorVersion: LiveStyle.modernMacOSVersion),
                       LiveStyle.modernFrameRadius)
        XCTAssertEqual(LiveStyle.frameRadius(majorVersion: 26), LiveStyle.modernFrameRadius)
        XCTAssertNotEqual(LiveStyle.modernFrameRadius, LiveStyle.legacyFrameRadius,
                          "порог по версии перестал что-либо менять")

        // Необязательный ключ frameRadius живого claude.json перебивает мажор; мусор и значения вне 0…40 — мимо.
        XCTAssertEqual(LiveStyle.frameRadius(config: "{\"frameRadius\":12}", majorVersion: 15), 12)
        XCTAssertEqual(LiveStyle.frameRadius(config: "{\"frameRadius\":0}", majorVersion: 26), 0)
        XCTAssertEqual(LiveStyle.frameRadius(config: "{\"frameRadius\":\(LiveStyle.maxFrameRadius + 1)}",
                                             majorVersion: 15), LiveStyle.legacyFrameRadius)
        XCTAssertEqual(LiveStyle.frameRadius(config: "{\"frameRadius\":-1}", majorVersion: 15),
                       LiveStyle.legacyFrameRadius)
        XCTAssertEqual(LiveStyle.frameRadius(config: "{\"frameRadius\":\"толще\"}", majorVersion: 26),
                       LiveStyle.modernFrameRadius)
        XCTAssertEqual(LiveStyle.frameRadius(config: "не json", majorVersion: 15), LiveStyle.legacyFrameRadius)
        XCTAssertEqual(LiveStyle.frameRadius(config: nil, majorVersion: 15), LiveStyle.legacyFrameRadius)

        // Инлайн-радиус самой рамки в inject.js — та же десятка: на macOS 13–15 угол ровный
        // без единой строки в claude.css. Именно это и просим глазами подтвердить у команды.
        let inject = try String(contentsOf: ClaudeAXTests.injectURL, encoding: .utf8)
        let marker = "const WINDOW_FRAME_RADIUS = "
        guard let found = inject.range(of: marker) else {
            return XCTFail("в inject.js не нашлась константа «\(marker)»")
        }
        XCTAssertEqual(Int(inject[found.upperBound...].prefix { $0.isNumber }), LiveStyle.legacyFrameRadius,
                       "рамка в inject.js рисуется не тем радиусом, который ждёт macOS 13–15")
    }

    /// Команда в Swift ↔ ветка разбора в inject.js (решение 9 плана WF24, находка К1 критика) — по общему
    /// списку `tests/fixtures/commands.json` (WF248), его же читает `tests/commands-contract.test.mjs`.
    /// Обе стороны: у `swift` и `ax-only` — случай ClaudeCommand (у `ax-only` ветки в inject.js нет);
    /// у `page-only` — ветка в inject.js и строка `"action"` в Swift-файле из записи (отправитель жив);
    /// у `legacy` строки в app/Sources нет (отправителя нет), ветка может и уйти. Новую команду —
    /// в commands.json, иначе тест красный.
    func testCommandContractMatchesInjectJS() throws {
        struct Entry: Decodable { let action: String; let sender: String; let file: String }
        struct List: Decodable { let commands: [Entry] }
        let list = try JSONDecoder().decode(List.self, from: Data(contentsOf: Repo.root
            .appendingPathComponent("tests/fixtures/commands.json")))
        var entries: [String: Entry] = [:]
        for entry in list.commands {
            XCTAssertNil(entries[entry.action], "«\(entry.action)» в commands.json дважды")
            XCTAssertTrue(["swift", "ax-only", "page-only", "legacy"].contains(entry.sender),
                          "у «\(entry.action)» чужой sender «\(entry.sender)»")
            entries[entry.action] = entry
        }
        func actions(_ senders: Set<String>) -> Set<String> {
            Set(entries.values.filter { senders.contains($0.sender) }.map { $0.action })
        }

        let inject = try String(contentsOf: ClaudeAXTests.injectURL, encoding: .utf8)
        let branches = Set(ClaudeAXTests.commandBranches(in: inject))
        XCTAssertFalse(branches.isEmpty, "в inject.js не нашлось ни одной ветки if (action === \"…\")")

        // Enum и список — одно множество; у `swift` ветка есть, у `ax-only` её нет.
        XCTAssertEqual(actions(["swift", "ax-only"]), Set(ClaudeCommand.allCases.map { $0.rawValue }),
                       "случаи ClaudeCommand и записи swift/ax-only в commands.json разошлись")
        for action in actions(["swift"]).sorted() {
            XCTAssertTrue(branches.contains(action),
                          "команда «\(action)» есть в Swift, а ветки в inject.js нет: допиши разбор или сделай её ax-only")
        }
        for action in actions(["ax-only"]).sorted() {
            XCTAssertFalse(branches.contains(action), "«\(action)» — ax-only, а в inject.js у неё ветка")
        }
        // Каждая ветка страницы кем-то названа.
        for branch in branches.sorted() {
            XCTAssertNotNil(entries[branch], "ветка «\(branch)» в inject.js без записи в tests/fixtures/commands.json")
        }
        // page-only: ветка есть, и Swift правда пишет эту строку там, где сказано.
        let sources = Repo.root.appendingPathComponent("app/Sources", isDirectory: true)
        for action in actions(["page-only"]).sorted() {
            XCTAssertTrue(branches.contains(action), "page-only «\(action)» без ветки в inject.js")
            let file = try XCTUnwrap(entries[action]?.file)
            XCTAssertTrue(file.hasPrefix("app/Sources/"), "у page-only «\(action)» file не в app/Sources: \(file)")
            // Тип, разрезанный на расширения (С4 WF248: `ClaudeAXController+Viewer.swift`), — тот же отправитель:
            // читаем файл из записи и его `<Имя>+*.swift` рядом.
            let named = Repo.root.appendingPathComponent(file)
            let stem = named.deletingPathExtension().lastPathComponent + "+"
            let parts = ((try? FileManager.default.contentsOfDirectory(at: named.deletingLastPathComponent(),
                                                                      includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.hasPrefix(stem) && $0.pathExtension == "swift" }
            let text = ([named] + parts).compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
            XCTAssertTrue(text.contains("\"\(action)\""),
                          "page-only «\(action)»: строки нет в \(file) и его расширениях — отправитель снят? тогда legacy")
        }
        // legacy: отправителя в Swift нет ни в одном файле.
        let swiftFiles = (FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? []).filter { $0.pathExtension == "swift" }
        XCTAssertFalse(swiftFiles.isEmpty)
        let allSwift = swiftFiles.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
        for action in actions(["legacy"]).sorted() {
            XCTAssertFalse(allSwift.contains("\"\(action)\""), "legacy «\(action)» снова пишет Swift — это page-only")
        }
    }

    /// Боевой inject.js из репозитория — тот самый файл, что уезжает в Claude (кладёт tools/bundle.sh).
    private static let injectURL = Repo.root
        .appendingPathComponent("claude-patch", isDirectory: true)
        .appendingPathComponent("inject.js")

    /// Ветки разбора команды: все `if (action === "…")` файла (раздел 15). Скобка в примете
    /// обязательна — без неё в список попадает `typeof detail?.action === "string"` парой строк выше.
    private static func commandBranches(in text: String) -> [String] {
        var found: [String] = []
        var rest = Substring(text)
        while let marker = rest.range(of: "(action === \"") {
            let tail = rest[marker.upperBound...]
            if let end = tail.firstIndex(of: "\"") { found.append(String(tail[..<end])) }
            rest = tail
        }
        return found
    }
}

final class FrameMatchTests: XCTestCase {
    /// Гейт WF36: рамка «встала», если все четыре величины в допуске 2 pt.
    func testFrameMatchesWithinTolerance() {
        let want = CGRect(x: 735, y: 34, width: 367, height: 859)
        XCTAssertTrue(ClaudeActions.frameMatches(CGRect(x: 736, y: 34, width: 367, height: 858), want))
        XCTAssertFalse(ClaudeActions.frameMatches(CGRect(x: 493, y: 74, width: 367, height: 819), want))
        XCTAssertFalse(ClaudeActions.frameMatches(CGRect(x: 735, y: 34, width: 367, height: 819), want))
    }
}

/// Какой из запущенных Claude «тот самый» (WF82, #7096). Ночью 23.09 на Маке жили два процесса
/// с bundle id Claude: забытая скрытая копия 1.20186.1 (запущена в 01:24, окна за экраном) и
/// настоящий 2.2553.13 (01:57). Кэш `running()` сел на первый и второго не замечал.
final class ClaudeInstanceTests: XCTestCase {
    private static let folders = ["/Applications", "/Users/u/Applications"]
    private let hidden = ClaudeInstance(pid: 41330, path: "/Applications/.Claude-before-Matrix-1.20186.1.app",
                                        launchDate: Date(timeIntervalSince1970: 1_790_108_640))
    private let regular = ClaudeInstance(pid: 49762, path: "/Applications/Claude.app",
                                         launchDate: Date(timeIntervalSince1970: 1_790_110_656))

    /// Весь сценарий ночи через `running()`: список процессов и часы подаются замыканиями.
    func testChoiceMovesToRegularClaudeLaunchedNextToHiddenCopy() {
        let app = IsolatedClaudeApp.make()
        var list = [hidden]
        var now: TimeInterval = 1_000
        var restarts = 0
        var windowQueries = 0
        var duplicates: [(path: String?, count: Int)] = []
        app.instances = { list }
        app.clock = { now }
        app.windowOwners = { windowQueries += 1; return [] }
        app.onRestart = { restarts += 1 }
        app.onDuplicate = { extra, count in duplicates.append((extra.path, count)) }

        // Только старый — выбран старый: другого нет, работаем с ним.
        _ = app.running()
        XCTAssertEqual(app.chosen?.pid, 41330)
        XCTAssertEqual(restarts, 0, "первая находка — не перезапуск")

        // Рядом запустился обычный. До сверки выбор стоит (running() зовут 8 раз в секунду),
        // на сверке — переезжает, и onRestart зовётся ровно один раз.
        list = [hidden, regular]
        now += 1
        _ = app.running()
        XCTAssertEqual(app.chosen?.pid, 41330, "список перечитывается раз в 2 с, не на каждом вызове")
        now += 1.5
        _ = app.running()
        XCTAssertEqual(app.chosen?.pid, 49762, "кэш держался за скрытую копию (#7096)")
        XCTAssertEqual(restarts, 1)
        XCTAssertEqual(windowQueries, 0, "место бандла решило без оконного сервера")
        XCTAssertEqual(duplicates.count, 1)
        XCTAssertEqual(duplicates.first?.path, "/Applications/.Claude-before-Matrix-1.20186.1.app")
        XCTAssertEqual(duplicates.first?.count, 2)
        for _ in 0..<5 {
            now += 3
            _ = app.running()
        }
        XCTAssertEqual(app.chosen?.pid, 49762)
        XCTAssertEqual(restarts, 1, "onRestart — ровно один раз на смену выбора")
        XCTAssertEqual(duplicates.count, 1, "плашка — одна на появление, а не на каждую сверку")

        // Старый вышел — выбор на месте, onRestart не зовётся.
        list = [regular]
        now += 3
        _ = app.running()
        XCTAssertEqual(app.chosen?.pid, 49762)
        XCTAssertEqual(restarts, 1)

        // Лишний запустили снова — снова одна плашка.
        list = [regular, hidden]
        now += 3
        _ = app.running()
        XCTAssertEqual(app.chosen?.pid, 49762)
        XCTAssertEqual(duplicates.count, 2)
        XCTAssertEqual(restarts, 1)
    }

    /// Перезапуск Claude, как было до WF82: вышел — выбора нет, запустился новый — onRestart.
    func testRelaunchStillCallsRestart() {
        let app = IsolatedClaudeApp.make()
        var list = [regular]
        var now: TimeInterval = 0
        var restarts = 0
        app.instances = { list }
        app.clock = { now }
        app.windowOwners = { [] }
        app.onRestart = { restarts += 1 }

        _ = app.running()
        XCTAssertEqual(app.chosen?.pid, 49762)
        list = []
        now += 3
        _ = app.running()
        XCTAssertNil(app.chosen)
        let next = ClaudeInstance(pid: 50001, path: "/Applications/Claude.app", launchDate: nil)
        list = [next]
        now += 1
        _ = app.running()
        XCTAssertNil(app.chosen, "без Claude список перечитывается не чаще раза в 2 с")
        now += 1.5
        _ = app.running()
        XCTAssertEqual(app.chosen?.pid, 50001)
        XCTAssertEqual(restarts, 1)
    }

    /// Порядок выбора (критик WF82 п. 3): место бандла, окна на экране, позже запущенный.
    func testPickOrder() {
        let folders = ClaudeInstanceTests.folders
        func at(_ minute: Double) -> Date { Date(timeIntervalSince1970: minute * 60) }
        let hidden = ClaudeInstance(pid: 10, path: "/Applications/.Claude-before-X.app", launchDate: at(5))
        let regular = ClaudeInstance(pid: 20, path: "/Applications/Claude.app", launchDate: at(1))
        let own = ClaudeInstance(pid: 30, path: "/Users/u/Applications/Claude.app", launchDate: at(2))
        let elsewhere = ClaudeInstance(pid: 40, path: "/Users/u/Downloads/Claude.app", launchDate: at(9))

        XCTAssertEqual(ClaudeApp.placement(of: regular.path, folders: folders), 0)
        XCTAssertEqual(ClaudeApp.placement(of: own.path, folders: folders), 0)
        XCTAssertEqual(ClaudeApp.placement(of: elsewhere.path, folders: folders), 1)
        XCTAssertEqual(ClaudeApp.placement(of: nil, folders: folders), 1)
        XCTAssertEqual(ClaudeApp.placement(of: hidden.path, folders: folders), 2)
        XCTAssertEqual(ClaudeApp.placement(of: "/Users/u/.Trash/Claude.app", folders: folders), 2)
        XCTAssertEqual(ClaudeApp.placement(of: "/Applications/Claude.app.failed", folders: folders), 2)

        // Место сильнее окон и возраста; кандидат один — оконный сервер не спрашиваем.
        var asked = 0
        XCTAssertEqual(ClaudeApp.pick([hidden, elsewhere, regular], folders: folders,
                                      windowOwners: { asked += 1; return [10, 40] })?.pid, 20)
        XCTAssertEqual(asked, 0)
        XCTAssertEqual(ClaudeApp.pick([hidden, elsewhere], folders: folders, windowOwners: { [10] })?.pid, 40)
        // Равные по месту — у кого окна на экране.
        XCTAssertEqual(ClaudeApp.pick([regular, own], folders: folders, windowOwners: { [20] })?.pid, 20)
        // Окна у обоих или ни у кого — позже запущенный.
        XCTAssertEqual(ClaudeApp.pick([regular, own], folders: folders, windowOwners: { [] })?.pid, 30)
        XCTAssertEqual(ClaudeApp.pick([own, regular], folders: folders, windowOwners: { [20, 30] })?.pid, 30)
        // Без даты запуска — больший pid.
        let a = ClaudeInstance(pid: 7, path: "/Applications/Claude.app", launchDate: nil)
        let b = ClaudeInstance(pid: 9, path: "/Users/u/Applications/Claude.app", launchDate: nil)
        XCTAssertEqual(ClaudeApp.pick([b, a], folders: folders, windowOwners: { [] })?.pid, 9)
        XCTAssertEqual(ClaudeApp.pick([a, b], folders: folders, windowOwners: { [] })?.pid, 9)
        XCTAssertNil(ClaudeApp.pick([], folders: folders, windowOwners: { [] }))
    }

    /// Живой выбор уступает только копии, что стоит лучше по месту: два Claude с окнами на
    /// разных столах не перекидывают выбор при каждом переключении стола.
    func testLiveChoiceMovesOnlyToBetterPlacement() {
        let folders = ClaudeInstanceTests.folders
        let one = ClaudeInstance(pid: 20, path: "/Applications/Claude.app", launchDate: nil)
        let two = ClaudeInstance(pid: 30, path: "/Users/u/Applications/Claude.app", launchDate: nil)
        var asked = 0
        XCTAssertEqual(ClaudeApp.choose(current: 30, among: [one, two], folders: folders,
                                        windowOwners: { asked += 1; return [20] })?.pid, 30)
        XCTAssertEqual(asked, 0, "живой выбор при равном месте окон не спрашивает")
        XCTAssertEqual(ClaudeApp.choose(current: hidden.pid, among: [hidden, regular], folders: folders,
                                        windowOwners: { [41330] })?.pid, 49762)
        // Выбранный вышел — выбор заново по полному порядку.
        XCTAssertEqual(ClaudeApp.choose(current: 99, among: [one, two], folders: folders,
                                        windowOwners: { [20] })?.pid, 20)
        XCTAssertEqual(ClaudeApp.choose(current: nil, among: [one, two], folders: folders,
                                        windowOwners: { [20] })?.pid, 20)
        XCTAssertNil(ClaudeApp.choose(current: 20, among: [], folders: folders, windowOwners: { [] }))
    }

    /// Лишний Claude появился рядом с выбранным настоящим: выбор на месте, перезапуска нет,
    /// плашка одна.
    func testHiddenCopyLaunchedLaterDoesNotStealChoice() {
        let app = IsolatedClaudeApp.make()
        var list = [regular]
        var now: TimeInterval = 0
        var restarts = 0
        var duplicates: [pid_t] = []
        app.instances = { list }
        app.clock = { now }
        app.windowOwners = { [] }
        app.onRestart = { restarts += 1 }
        app.onDuplicate = { extra, _ in duplicates.append(extra.pid) }

        _ = app.running()
        list = [regular, hidden]
        for _ in 0..<3 {
            now += 3
            _ = app.running()
        }
        XCTAssertEqual(app.chosen?.pid, 49762)
        XCTAssertEqual(restarts, 0)
        XCTAssertEqual(duplicates, [41330])
    }

    /// Плашка про лишний Claude (критик WF82 п. 4): путь отдельной строкой, чтобы не обрезался.
    func testDuplicateNoticeNamesTheExtraCopy() {
        XCTAssertEqual(MenuModel.duplicateClaudeNotice(path: "/Applications/.Claude-before-Matrix-1.20186.1.app",
                                                       pid: 41330, count: 2),
                       "Запущено два Claude:\n/Applications/.Claude-before-Matrix-1.20186.1.app,\n"
                       + "закрой его, иначе ломаются темы и меню")
        XCTAssertTrue(MenuModel.duplicateClaudeNotice(path: nil, pid: 41330, count: 3)
            .hasPrefix("Запущено 3 Claude:\nпроцесс 41330,"))
    }
}

/// Меню на выбранной кнопке и в полноэкранном режиме (WF82, #7104). Числа — живой замер
/// 23.09 на MacBook с вырезом (экран 1470×956, толщина строки меню 22).
final class MenuButtonTests: XCTestCase {
    private let yellow = CGRect(x: 43, y: 54, width: 16, height: 16)
    private let green = CGRect(x: 66, y: 54, width: 16, height: 16)

}
