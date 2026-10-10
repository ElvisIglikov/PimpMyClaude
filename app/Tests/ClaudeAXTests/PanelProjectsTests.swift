import XCTest
@testable import ClaudeAX

/// Проекты панели PMP (WF126, `docs/wf126-spec.md` §3): разбор сводки, фазы, готовые слова, кто куда попадает.
final class PanelProjectsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private static let vkusnoff = """
    # 🟠VkusnoffKz
    обновлено 03:05

    1️⃣ Workflow ✅ готово
    - о чём: «В корзине · N» открывает то, что лежит в корзине
    - шаги 3 из 3
    - 01:11 → 02:41 · 1,5 ч
    - планирование · я · Opus 5.5 high
    - кодинг · 2 агента · Opus 5.5 medium и high

    3️⃣ Workflow 💭 идёт
    - о чём: Kimi K3 и GLM читают весь код по модулям
    - шаги 1 из 4
    - 01:32 → закончит в 11:00 · идёт 28 мин
    - прошлые шаги: кодинг — 1 агент, Opus 5.5 high, стенд на 29 зон
    - проверка · Kimi K3 max и GLM-5.3-Flash max читают, сдано 3 зоны из 29
    - проверка · судья на 2 зоны · Opus 5.5 xhigh 💭

    4️⃣ Workflow запланирован
    - о чём: выкладка

    Сейчас: карточка блюда починена
    **Ждёт Элвиса:** «вливай PR 9»; «ставь 191»
    """

    func testHeadingMarkerTailAndBlocks() {
        let status = PanelProjects.parse(Self.vkusnoff)
        XCTAssertEqual(status.marker, "🟠")
        XCTAssertEqual(status.name, "VkusnoffKz")
        XCTAssertEqual(status.now, "карточка блюда починена")
        XCTAssertEqual(status.waitFor, "«вливай PR 9»; «ставь 191»", "жирное прощается")
        XCTAssertEqual(status.workflows.map { $0.state }, [.done, .running, .planned])
        let done = status.workflows[0]
        XCTAssertEqual(done.about, "«В корзине · N» открывает то, что лежит в корзине", "«о чём:» снято")
        XCTAssertEqual(done.stepsDone, 3)
        XCTAssertEqual(done.stepsTotal, 3)
        XCTAssertEqual(done.duration, "1,5 ч")
        XCTAssertEqual(done.phases.map { $0.state }, [.done, .done])
        XCTAssertEqual(done.phases.map { $0.name }, ["план", "кодинг"])
        XCTAssertEqual(PanelProjects.parse("# Rick\n").marker, "")
        XCTAssertEqual(PanelProjects.parse("# Rick\n").name, "Rick")
        XCTAssertEqual(PanelProjects.parse("1️⃣ Workflow 🛑 упал\n- о чём: x\n").workflows.first?.state, .failed)
        XCTAssertEqual(PanelProjects.parse("1️⃣ Workflow ✋ жду\n- о чём: x\n").workflows.first?.state, .waiting)
    }

    func testPhasesPastWithDashMergeAndRunningMark() {
        let running = PanelProjects.parse(Self.vkusnoff).workflows[1]
        // Прошлые «кодинг — …» → «кодинг»; две роли «проверка» — один отрезок; текущий — роль с 💭.
        XCTAssertEqual(running.phases.map { $0.name }, ["кодинг", "проверка"])
        XCTAssertEqual(running.phases.map { $0.state }, [.done, .current])
        XCTAssertEqual(running.phases[1].effort, "EXTRA", "xhigh → EXTRA")
        XCTAssertEqual(running.phases[1].who, "судья на 2 зоны · Opus 5.5")
        XCTAssertFalse(running.phases[1].hot)
        XCTAssertEqual(running.phases[1].help, "проверка · судья на 2 зоны · Opus 5.5 xhigh 💭")
        XCTAssertEqual(running.phases[0].who, "", "у прошлых модель не показываем")
    }

    func testPhasesWithoutRunningMarkTakeLastRoleAndHotModels() {
        let text = """
        1️⃣ Workflow 💭 идёт
        - о чём: панель
        - планирование · я · Opus 5.5 high
        - критика · 1 агент · 🔴 **Fable max**
        - кодинг · 2 агента · Opus 5.5 medium
        - проверка · 1 агент · Opus 5.5 high
        """
        let phases = PanelProjects.parse(text).workflows[0].phases
        XCTAssertEqual(phases.map { $0.state }, [.done, .done, .done, .current], "без 💭 текущая — последняя роль")
        XCTAssertEqual(phases[3].who, "1 × Opus 5.5")
        XCTAssertEqual(phases[3].effort, "HIGH")
        XCTAssertEqual(phases[0].name, "план")
        XCTAssertEqual(phases[0].who, "я · Opus 5.5")
        XCTAssertEqual(phases[1].who, "1 × Fable")
        XCTAssertEqual(phases[1].effort, "MAX")
        XCTAssertTrue(phases[1].hot, "Fable и max — красным")
        XCTAssertEqual(phases[2].who, "2 × Opus 5.5")

        let marked = PanelProjects.parse(text.replacingOccurrences(of: "Opus 5.5 medium", with: "Opus 5.5 medium 💭"))
            .workflows[0].phases
        XCTAssertEqual(marked.map { $0.state }, [.done, .done, .current, .future])
        XCTAssertEqual(marked[3].who, "1 × Opus 5.5", "будущая — с моделью")

        let failed = PanelProjects.parse(text.replacingOccurrences(of: "💭 идёт", with: "🛑 упал")).workflows[0]
        XCTAssertEqual(failed.phases.last?.state, .failed)
        let planned = PanelProjects.parse(text.replacingOccurrences(of: "💭 идёт", with: "запланирован")).workflows[0]
        XCTAssertTrue(planned.phases.allSatisfy { $0.state == .future })

        let many = ["а", "б", "в", "г", "д", "е", "ж"].map { "- \($0) · 1 агент · Opus 5.5 high" }.joined(separator: "\n")
        XCTAssertEqual(PanelProjects.parse("1️⃣ Workflow 💭\n- о чём: x\n" + many).workflows[0].phases.count, 5)
        XCTAssertEqual(PanelProjects.shortName("архитектура"), "архитект…")
    }

    func testUnparsedRoleKeepsWholeLine() {
        let phases = PanelProjects.parse("1️⃣ Workflow 💭\n- о чём: x\n- проверка · Kimi K3 и GLM читают 💭\n")
            .workflows[0].phases
        XCTAssertEqual(phases.first?.who, "Kimi K3 и GLM читают")
        XCTAssertEqual(phases.first?.effort, "")
    }

    func testReadyWords() {
        // Строки таблицы §3.4.
        var split = PanelProjects.words("«вливай подписи» и «вливай закреплённые»; «запускай марафон»")
        XCTAssertEqual(split.words, ["вливай подписи", "вливай закреплённые", "запускай марафон"])
        XCTAssertEqual(split.note, "")
        split = PanelProjects.words("посмотреть `docs/22.html`; отправить коллеге архив из «Загрузок»; «запускай марафон»")
        XCTAssertEqual(split.words, ["запускай марафон"])
        XCTAssertEqual(split.note, "посмотреть `docs/22.html`; отправить коллеге архив из «Загрузок»")
        split = PanelProjects.words("«да» шот-листу (6 кадров), картинам в зал…; номера стилей «Ста креативов»")
        XCTAssertEqual(split.words, [])
        XCTAssertEqual(split.note, "«да» шот-листу (6 кадров), картинам в зал…; номера стилей «Ста креативов»")
        split = PanelProjects.words("записи Plaud для замера голосов (4.1) и слово на установку 191 (5.1)")
        XCTAssertEqual(split.words, [])
        XCTAssertEqual(PanelProjects.words("«вливай PR 9»; «ставь 191».").words, ["вливай PR 9", "ставь 191"])
        XCTAssertEqual(PanelProjects.words("«а», «б» или «в»; «г»").words, ["а", "б", "в"], "до трёх")
        XCTAssertEqual(PanelProjects.words("«а», «б» или «в»; «г»").note, "«г»")
        XCTAssertEqual(PanelProjects.words("«\(String(repeating: "я", count: 61))»").words, [], "длиннее 60 — не кнопка")
        for nothing in ["ничего", "нет.", "—", ""] { XCTAssertTrue(PanelProjects.isNothing(nothing), nothing) }
        XCTAssertFalse(PanelProjects.isNothing("«да»"))
    }

    // MARK: обход папок

    private func makeTemp() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("panel-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    @discardableResult
    private func write(_ root: URL, _ project: String, _ text: String, sub: String = "docs", age: TimeInterval) -> URL {
        let folder = root.appendingPathComponent(project).appendingPathComponent(sub)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("status.md")
        try? text.write(to: file, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: file.path)
        return file
    }

    func testSnapshotSectionsThresholdsWorktreesAndSymlinks() throws {
        let root = makeTemp()
        let fm = FileManager.default
        write(root, "Waiter", "# 🟢Waiter\nЖдёт Элвиса: «да»\n", age: 3600)
        write(root, "OldWaiter", "# OldWaiter\nЖдёт Элвиса: «да»\n", age: 8 * 86_400)
        write(root, "Runner", "# Runner\n1️⃣ Workflow 💭 идёт\n- о чём: x\n- кодинг · 1 агент · Opus 5.5 high\n"
              + "Ждёт Элвиса: ничего\n", sub: "audit", age: 3 * 3600)
        write(root, "StaleRunner", "# StaleRunner\n1️⃣ Workflow 💭 идёт\n- о чём: x\n", age: 13 * 3600)
        write(root, "Hand", "# Hand\n1️⃣ Workflow ✋ жду\n- о чём: макет\n", age: 60)
        // Рабочее дерево: `.git` — файл.
        write(root, "Runner-wt", "# Runner\n1️⃣ Workflow 💭 идёт\n- о чём: x\n", age: 60)
        try "gitdir: /x".write(to: root.appendingPathComponent("Runner-wt/.git"), atomically: true, encoding: .utf8)
        // Rick/docs/status.md → Waiter/docs/status.md: одна сводка — один проект.
        try fm.createDirectory(at: root.appendingPathComponent("Rick/docs"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: root.appendingPathComponent("Rick/docs/status.md"),
                                  withDestinationURL: root.appendingPathComponent("Waiter/docs/status.md"))
        try fm.createDirectory(at: root.appendingPathComponent("Empty"), withIntermediateDirectories: true)

        let snapshot = PanelProjects.snapshot(root: root, recent: [(folder: root.appendingPathComponent("Empty"), name: "Empty")],
                                              mainEntry: "Rick", now: now)
        XCTAssertEqual(snapshot.waiting.map { $0.name }, ["Hand", "Waiter"], "свежие первыми, старше 7 суток — нет")
        XCTAssertEqual(snapshot.waiting.first?.note, "Workflow «макет» ждёт тебя")
        XCTAssertEqual(snapshot.waiting.last?.words, ["да"])
        XCTAssertEqual(snapshot.waiting.last?.marker, "🟢")
        XCTAssertEqual(snapshot.working.map { $0.name }, ["Runner"], "старше 12 ч и рабочее дерево — нет; «ничего» — не ждёт")
        XCTAssertEqual(snapshot.working.first?.running.first?.phases.first?.state, .current)
        XCTAssertEqual(snapshot.others.map { $0.name }.first, "Rick", "главный — первым")
        XCTAssertTrue(snapshot.others.contains { $0.name == "Empty" }, "недавний без сводки — в «Остальных»")
        XCTAssertFalse(snapshot.others.contains { $0.name == "Waiter" }, "уже в «Ждут»")
        XCTAssertEqual(snapshot.others.first { $0.name == "Rick" }?.updated, nil, "сводка-ссылка на чужую — не своя")
        XCTAssertTrue(snapshot.others.contains { $0.name == "StaleRunner" }, "сводка младше 7 суток — в «Остальных»")
        XCTAssertFalse(snapshot.others.contains { $0.name == "OldWaiter" })
        XCTAssertFalse((snapshot.waiting + snapshot.working + snapshot.others).contains { $0.folder.hasSuffix("Runner-wt") })
        XCTAssertEqual(snapshot.mainName, "Rick")
        XCTAssertTrue(snapshot.others.first?.isMain ?? false)
    }
}
