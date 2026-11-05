import CoreGraphics
import XCTest
@testable import ClaudeAX

/// WF242 (слово Элвиса 11.10.2026 01:40, панель у часов): графики плавные и без вылетов, память красная там, где
/// своп; отсчёты в цветах темы, оживают под курсором, второе нажатие — настройки; раскрытый график — своим рядом;
/// «Анализ памяти» — поручение из файла, который человек правит под себя.
final class PanelWF242Tests: XCTestCase {
    private static let gb: UInt64 = 1_073_741_824
    private static let mb: UInt64 = 1_048_576
    private static let t0 = Date(timeIntervalSince1970: 1_791_500_000)

    // MARK: плавная линия

    func testSmoothingKeepsEndsStaysInsideRangeAndCalmsRipple() {
        let raw: [Double] = [50, 56, 51, 55, 50, 71, 52, 57, 47, 54, 49, 55, 50, 56]
        let smooth = ChartCurve.smoothed(raw)
        XCTAssertEqual(smooth.count, raw.count)
        XCTAssertEqual(smooth.last, raw.last, "«сейчас» — то же число, что в строке")
        XCTAssertTrue(smooth.allSatisfy { (47...71).contains($0) }, "сглаживание не выходит за крайние значения")
        func ripple(_ values: [Double]) -> Double { zip(values, values.dropFirst()).reduce(0) { $0 + abs($1.1 - $1.0) } }
        XCTAssertLessThan(ripple(smooth), ripple(raw) / 3, "пилы между соседними минутами нет")
        // Подъём на десяток минут — это данные, а не рябь: он остаётся на месте и почти в свой рост.
        let hill: [Double] = Array(repeating: 50, count: 10) + Array(repeating: 80, count: 12) + Array(repeating: 50, count: 10)
        let calm = ChartCurve.smoothed(hill)
        XCTAssertEqual(calm[15], 80, accuracy: 0.5)
        XCTAssertEqual(calm[2], 50, accuracy: 0.001)
        XCTAssertEqual(ChartCurve.smoothed(raw, passes: 0), raw)
        XCTAssertEqual(ChartCurve.smoothed([3, 9]), [3, 9], "две точки сглаживать нечем")
        XCTAssertEqual(ChartCurve.smoothed([]), [])
    }

    /// Кривая между соседними точками не вылетает за их значения — зубцов выше максимума и ниже минимума нет.
    func testCurveNeverOvershootsItsPoints() {
        let ys: [CGFloat] = [40, 40, 90, 20, 21, 80, 80, 10, 55, 54, 100, 0]
        var x: CGFloat = 0
        let points = ys.enumerated().map { index, y -> CGPoint in
            x += index % 3 == 0 ? 1 : 7 // шаг по времени неровный
            return CGPoint(x: x, y: y)
        }
        let controls = ChartCurve.controls(points)
        XCTAssertEqual(controls.count, points.count - 1)
        for index in controls.indices {
            let from = points[index], to = points[index + 1]
            let low = min(from.y, to.y) - 0.0001, high = max(from.y, to.y) + 0.0001
            XCTAssertTrue(controls[index].c1.x > from.x && controls[index].c2.x < to.x, "опорные точки — между концами")
            for step in 0...20 {
                let y = ChartCurve.bezierY(from, controls[index].c1, controls[index].c2, to, at: CGFloat(step) / 20)
                XCTAssertTrue((low...high).contains(y), "отрезок \(index): \(y) вне \(from.y)…\(to.y)")
            }
        }
        XCTAssertTrue(ChartCurve.controls([CGPoint(x: 1, y: 1)]).isEmpty)
    }

    // MARK: память — своп

    private func sample(_ minute: Double, swap: UInt64?, level: MemoryPressureLevel = .normal,
                        total: UInt64 = 16 * PanelWF242Tests.gb) -> MacMemorySample {
        MacMemorySample(at: Self.t0.addingTimeInterval(minute * 60), pressure: 50, level: level,
                        used: 10 * Self.gb, total: total, swap: swap)
    }

    func testMemoryIsLoadedWhereSwapGrowsOrStaysHigh() {
        let history = [
            sample(0, swap: 300 * Self.mb),           // старый хвост в свопе — спокойно
            sample(1, swap: 310 * Self.mb),           // рябь в 10 МБ — спокойно
            sample(2, swap: 500 * Self.mb),           // +190 МБ за минуту — растёт
            sample(3, swap: 900 * Self.mb),           // растёт
            sample(4, swap: 900 * Self.mb),           // встал, до четверти памяти далеко — спокойно
            sample(5, swap: 850 * Self.mb),           // убывает — спокойно
            sample(6, swap: 4 * Self.gb + 1),         // рост и четверть от 16 ГБ
            sample(7, swap: 4 * Self.gb),             // не растёт, но держится высоко
        ]
        XCTAssertEqual(MacMemory.loaded(history), [false, false, true, true, false, false, true, true])
        XCTAssertEqual(MacMemory.swapLoad(history, at: 3), .growing)
        XCTAssertEqual(MacMemory.swapLoad(history, at: 7), .high)
        // Порог «высоко» — от памяти Мака: те же 2 ГБ на Маке с 8 ГБ — уже четверть.
        XCTAssertEqual(MacMemory.loaded([sample(0, swap: 2 * Self.gb, total: 8 * Self.gb)]), [true])
        XCTAssertEqual(MacMemory.loaded([sample(0, swap: 2 * Self.gb)]), [false])
        // Уровень macOS при известном свопе красного не даёт: «нагружена — когда своп».
        XCTAssertEqual(MacMemory.loaded([sample(0, swap: 0, level: .warn)]), [false])
        // После сна Мака прошлое чтение — не «минуту назад»: скачок через разрыв ростом не считается.
        XCTAssertEqual(MacMemory.loaded([sample(0, swap: 100 * Self.mb), sample(40, swap: 900 * Self.mb)]), [false, false])
    }

    func testMemoryWordsSpeakAboutSwap() {
        let growing = [sample(0, swap: 300 * Self.mb), sample(1, swap: 2 * Self.gb)]
        XCTAssertEqual(MacMemory.captionParts(growing).word, "своп растёт")
        XCTAssertEqual(MacMemory.captionParts(growing).rest, "за 1 мин без изменений · в свопе 2 ГБ")
        XCTAssertEqual(MacMemory.captionParts([sample(0, swap: 5 * Self.gb), sample(1, swap: 5 * Self.gb)]).word, "много в свопе")
        let calm = [sample(0, swap: 300 * Self.mb), sample(1, swap: 300 * Self.mb)]
        XCTAssertEqual(MacMemory.captionParts(calm).word, "", "спокойно — слова нет")
        XCTAssertEqual(MacMemory.captionParts(calm).rest, "за 1 мин без изменений · в свопе 0.3 ГБ")
        XCTAssertNil(MacMemory.swapText(sample(0, swap: 0)))
        XCTAssertNil(MacMemory.swapText(sample(0, swap: 40 * Self.mb)), "меньше 0,1 ГБ не пишем")
        XCTAssertNil(MacMemory.swapText(sample(0, swap: nil)))
        XCTAssertEqual(MacMemory.help(growing), "Память: занято 10 из 16 ГБ — 63 % · в норме · в свопе 2 ГБ")
    }

    func testSwapIsReadFromThisMac() {
        // Настоящее чтение ядра: число есть и не больше разумного (петабайт).
        let swap = MemoryReader.swapUsedBytes()
        XCTAssertNotNil(swap, "vm.swapusage читается без прав")
        XCTAssertLessThan(swap ?? 0, 1 << 50)
    }

    // MARK: отсчёты

    func testCountdownTilesTakeColorsOfWindowTheme() {
        let themes = [WindowColorChip(id: "violet", name: "Фиолетовая", background: "#1b1230", accent: "#b57bff", light: false),
                      WindowColorChip(id: "mint", name: "Мятная", background: "#eafaf1", accent: "#1f9d6b", light: true)]
        let violet = PanelCountdown.palette(.theme("violet"), themes: themes, dark: true)
        XCTAssertEqual(violet.accent, 0xB57BFF, "плитка — в акценте темы окон, а не оранжевая")
        XCTAssertEqual(violet.background, 0x1B1230)
        XCTAssertEqual(violet.ink, 0xECECEE)
        let mint = PanelCountdown.palette(.theme("mint"), themes: themes, dark: true)
        XCTAssertEqual(mint.accent, 0x1F9D6B)
        XCTAssertEqual(mint.ink, 0x1F1E1D, "светлая тема — тёмный текст")
        XCTAssertNotEqual(mint.field, mint.background, "поле ввода чуть отличается от фона окна")
        // «Как у Claude», «по проектам» и тема, которой нет в каталоге, — оранжевый Claude.
        for choice in [WindowColorChoice.plain, .byProject, .theme("gone")] {
            XCTAssertEqual(PanelCountdown.palette(choice, themes: themes, dark: true).accent, 0xD97757)
        }
        XCTAssertEqual(PanelCountdown.palette(.plain, themes: [], dark: false).background, 0xFAF9F5)
        XCTAssertEqual(ColorMath.mix(0xFFFFFF, 0x000000, 0.5), 0x808080)
        XCTAssertEqual(ColorMath.mix(0x102030, 0xA0B0C0, 1), 0x102030)
        XCTAssertEqual(ColorMath.mix(0x102030, 0xA0B0C0, 0), 0xA0B0C0)
    }

    func testCountdownFramesCountThreeTwoOneThenLaunchAndRepeat() {
        let second = PanelCountdown.second
        XCTAssertEqual(PanelCountdown.frame(at: 0).digit, 3)
        XCTAssertEqual(PanelCountdown.frame(at: second * 1.5).digit, 2)
        XCTAssertEqual(PanelCountdown.frame(at: second * 2.5).digit, 1)
        XCTAssertEqual(PanelCountdown.frame(at: second * 1.5).beat, 0.5, accuracy: 0.0001)
        XCTAssertEqual(PanelCountdown.frame(at: second * 1.5).passed, 0.5, accuracy: 0.0001)
        XCTAssertNil(PanelCountdown.frame(at: second * 2.9).flight, "идёт счёт — пуска нет")
        let flying = PanelCountdown.frame(at: second * 3 + PanelCountdown.launch / 2)
        XCTAssertEqual(flying.digit, 0)
        XCTAssertEqual(flying.flight ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(PanelCountdown.frame(at: PanelCountdown.loop - 0.01).flight, 1, "пауза перед повтором")
        let again = PanelCountdown.frame(at: PanelCountdown.loop + second * 1.5)
        XCTAssertEqual(again.digit, 2, "круг повторяется")
        XCTAssertEqual(again.beat, 0.5, accuracy: 0.0001)
        // В покое — цифра «3»; оживая, вид играет с этого же кадра, без скачка.
        XCTAssertEqual(PanelCountdown.still.digit, 3)
        XCTAssertEqual(PanelCountdown.still, PanelCountdown.frame(at: PanelCountdown.stillTime))
        XCTAssertNil(PanelCountdown.still.flight)
    }

    func testCountdownPlaysOnlyUnderRestingCursor() {
        var hover = CountdownHover()
        XCTAssertNil(hover.playing, "в покое плитки неподвижны")
        hover.enter("1.8")
        XCTAssertEqual(hover.hovered, "1.8")
        XCTAssertNil(hover.playing, "навёл — ещё не играет: задержка")
        hover.rested("1.8")
        XCTAssertEqual(hover.playing, "1.8")
        // Перевёл на соседнюю: прежняя замерла сразу, новая ждёт свою задержку; порядок «вошёл — вышел» любой.
        hover.enter("1.9")
        XCTAssertNil(hover.playing)
        hover.leave("1.8")
        XCTAssertEqual(hover.hovered, "1.9")
        hover.rested("1.8")
        XCTAssertNil(hover.playing, "поздний сигнал от прошлой плитки ничего не оживляет")
        hover.rested("1.9")
        XCTAssertEqual(hover.playing, "1.9")
        hover.leave("1.9")
        XCTAssertEqual(hover, CountdownHover(), "ушёл — замерло")
        XCTAssertEqual(PanelCountdown.hoverDelay, 0.3, accuracy: 0.0001)
    }

    func testSecondTapOnSelectedTileOpensItsSettings() {
        XCTAssertEqual(PanelCountdown.tap(style: "1.9", selected: "1.8", settingsOpen: false), .select)
        XCTAssertEqual(PanelCountdown.tap(style: "1.9", selected: "1.8", settingsOpen: true), .select,
                       "другая плитка при открытых настройках — выбор, настройки остаются и теперь её")
        XCTAssertEqual(PanelCountdown.tap(style: "1.8", selected: "1.8", settingsOpen: false), .settings(open: true))
        XCTAssertEqual(PanelCountdown.tap(style: "1.8", selected: "1.8", settingsOpen: true), .settings(open: false))
    }

    func testCountdownSizeSliderAndTileScale() {
        XCTAssertEqual(PanelCountdown.sizeRange, 60...200)
        XCTAssertEqual(PanelCountdown.size(134), 130)
        XCTAssertEqual(PanelCountdown.size(20), 60)
        XCTAssertEqual(PanelCountdown.size(999), 200)
        XCTAssertTrue(PanelCountdown.sizeMarks.allSatisfy { PanelCountdown.sizeRange.contains($0) && PanelCountdown.size($0) == $0 })
        XCTAssertEqual(PanelCountdown.tileScale(size: 100), 1, accuracy: 0.0001)
        XCTAssertEqual(PanelCountdown.tileScale(size: 60), 0.8, accuracy: 0.0001)
        XCTAssertEqual(PanelCountdown.tileScale(size: 200), 1.5, accuracy: 0.0001)
        let scales = stride(from: 60, through: 200, by: 10).map { PanelCountdown.tileScale(size: $0) }
        XCTAssertEqual(scales, scales.sorted(), "больше размер — крупнее ракета в плитке")
    }

    /// Размер из панели уходит страницам той же командой `send-look`, вид не трогает.
    func testSizeGoesToPagesAndKeepsStyle() throws {
        let suite = testSuiteName()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = PageLookSettings(defaults: defaults)
        var sent: [[String: String]] = []
        settings.write = { action, fields, _ in
            var row = ["action": action]
            for field in fields {
                switch field.value {
                case .string(let text): row[field.key] = text
                case .number(let number): row[field.key] = "\(number)"
                case .bool(let flag): row[field.key] = flag ? "true" : "false"
                default: break
                }
            }
            sent.append(row)
            return true
        }
        XCTAssertEqual(settings.current.size, 150, "ключа нет — 150 % (решение 03.11.2026)")
        settings.setLook(style: "1.9")
        settings.setLook(size: PanelCountdown.size(157))
        XCTAssertEqual(settings.current.size, 160)
        XCTAssertEqual(settings.current.style, "1.9")
        XCTAssertEqual(sent.last, ["action": "send-look", "style": "1.9", "size": "160", "preview": "false"])
    }

    // MARK: имя цвета

    func testColorNameIsHoveredOrChosen() {
        let themes = [WindowColorChip(id: "violet", name: "Фиолетовая", background: "#1b1230", accent: "#b57bff", light: false),
                      WindowColorChip(id: "coral", name: "Коралл", background: "#2a1512", accent: "#ff7a66", light: false)]
        XCTAssertEqual(PanelColorTiles.shownName(hovered: nil, choice: .theme("violet"), themes: themes), "Фиолетовая")
        XCTAssertEqual(PanelColorTiles.shownName(hovered: .theme("coral"), choice: .theme("violet"), themes: themes), "Коралл",
                       "под курсором — имя образца, сразу")
        XCTAssertEqual(PanelColorTiles.shownName(hovered: .plain, choice: .theme("violet"), themes: themes), "Как у Claude")
        XCTAssertEqual(PanelColorTiles.shownName(hovered: nil, choice: .plain, themes: themes), "Как у Claude")
        XCTAssertEqual(PanelColorTiles.shownName(hovered: nil, choice: .byProject, themes: themes), "Свой у каждого проекта")
        XCTAssertEqual(PanelColorTiles.shownName(hovered: nil, choice: .theme("gone"), themes: themes), "")
    }

    // MARK: раскрытый график — своим рядом

    func testExpandedChartTakesFullRowAndLayoutIsUntouched() {
        let all = Set(PanelWidget.allCases.map { $0.rawValue })
        let layout = PanelWidgetLayout.unfolded
        func ids(_ expanded: Set<String>) -> [[String]] { layout.rows(visible: all, expanded: expanded).map { $0.map { $0.id } } }
        XCTAssertTrue(ids([]).contains(["temperature", "memory"]), "свёрнутые — половинками рядом")
        XCTAssertEqual(ids([]), layout.rows(visible: all).map { $0.map { $0.id } })
        let memory = ids(["memory"])
        XCTAssertTrue(memory.contains(["temperature"]) && memory.contains(["memory"]))
        XCTAssertLessThan(memory.firstIndex(of: ["temperature"]) ?? 99, memory.firstIndex(of: ["memory"]) ?? -1)
        let both = ids(["temperature", "memory"])
        XCTAssertEqual(both.firstIndex(of: ["memory"]), (both.firstIndex(of: ["temperature"]) ?? -9) + 1,
                       "оба раскрыты — друг под другом")
        XCTAssertTrue(both.contains(["week", "reset"]) && both.contains(["limits", "fable"]), "прочие ряды — как были")
        XCTAssertEqual(layout.item("memory")?.wide, false, "раскладка человека не меняется: свернул — снова половинка")
    }

    // MARK: «Анализ памяти»

    func testMemoryPromptFileIsCreatedOnceAndBelongsToThePerson() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wf242-prompts-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent(ChatStarter.memoryFileName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let first = try ChatStarter.memoryPrompt(directory: dir)
        XCTAssertTrue(first.hasPrefix("Проведи анализ памяти"))
        XCTAssertTrue(first.contains(dir.appendingPathComponent(ChatStarter.memoryNotesFileName).path),
                      "нейронку просят вести заметки прошлых разборов в файле рядом")
        XCTAssertTrue(first.contains("прочитай заметки прошлых разборов"), "и читать их в начале")
        XCTAssertTrue(first.contains(file.path), "текст говорит, где он лежит, — править под себя")
        XCTAssertTrue(first.contains("без моего «да»"), "ничего не закрывать без слова человека")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), first + "\n")
        // Человек поправил — его текст и вставляется, файл не перезаписывается.
        try "Мой разбор памяти: только своп.\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(try ChatStarter.memoryPrompt(directory: dir), "Мой разбор памяти: только своп.\n")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "Мой разбор памяти: только своп.\n")
        // Пустой файл — вставляется умолчание, файл не трогаем.
        try " \n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(try ChatStarter.memoryPrompt(directory: dir), first)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), " \n")
    }

    /// Поручение ложится в поле ввода командой «Workflow» (вставить и не отправлять), адрес — одному окну.
    func testStarterGoesAsWorkflowInsertToOneWindow() throws {
        func row(_ fields: [(key: String, value: CommandValue)]) -> [String] {
            fields.map { field in
                if case .string(let text) = field.value { return field.key + "=" + text }
                return field.key
            }
        }
        XCTAssertEqual(row(ClaudeActions.starterFields(text: "т", match: "/epitaxy", chat: nil)),
                       ["scope=window", "title=", "text=т", "match=/epitaxy"])
        XCTAssertEqual(row(ClaudeActions.starterFields(text: "т", match: nil, chat: "local_1")),
                       ["scope=window", "title=", "text=т", "chat=local_1"])
        XCTAssertEqual(row(ClaudeActions.starterFields(text: "т", match: nil, chat: nil)),
                       ["scope=window", "title=", "text=т"], "без адреса — окно в фокусе")
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wf242-cmd-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("command.json")
        let actions = ClaudeActions(app: IsolatedClaudeApp.make(),
                                    commands: CommandChannel(path: file, now: { Date() }, schedule: { _, _ in }))
        actions.insertStarter(text: "Проведи анализ памяти", match: "/epitaxy", chat: nil)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(json["action"] as? String, "workflow", "страница вставляет текст и не отправляет")
        XCTAssertEqual(json["text"] as? String, "Проведи анализ памяти")
        XCTAssertEqual(json["match"] as? String, "/epitaxy")
    }
}
