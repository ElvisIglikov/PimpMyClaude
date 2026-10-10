import AppKit
import XCTest
@testable import ClaudeAX

/// Батч AS WF92 (#7704): кружок-микрофон не жмёт клавишу Диктатора, пока тот уже пишет не с
/// этого кружка, — нажатой странице `mic-refused`, человеку «Сначала останови запись в Диктаторе».
/// AS2: пауза Диктатора, хозяин записи устаревает, ключ по окну, адресный отказ, край значка.
/// Всё на подставных данных: ни мыши, ни Диктатора, ни живого Claude.
final class MicWF92Tests: XCTestCase {
    private final class Box {
        var state: DictatorState = .idle
        var keys = 0
        var refused: [(chat: String?, match: String)] = []
        var notices: [String] = []
        var now = Date(timeIntervalSince1970: 1_000_000)
        var asked = 0
    }

    /// Подставной Диктатор: клавиша в покое — пишет, при записи — в покой, на паузе — пишет.
    private func rig() -> (MicMonitor, Box) {
        let box = Box()
        let monitor = MicMonitor()
        monitor.dictatorState = { box.asked += 1; return box.state }
        monitor.postKey = {
            box.keys += 1
            box.state = box.state == .recording ? .idle : .recording
        }
        monitor.sendRefused = { chat, match in box.refused.append((chat, match)); return true }
        monitor.notice = { box.notices.append($0) }
        monitor.now = { box.now }
        return (monitor, box)
    }

    private func later(_ box: Box, _ seconds: TimeInterval) {
        box.now = box.now.addingTimeInterval(seconds)
    }

    // MARK: - состояние по плашке

    func testStateFromMenuBarPlate() {
        let square = CGSize(width: 24, height: 24)
        XCTAssertEqual(DictatorRecording.state(size: square, description: "Dictator"), .idle)
        XCTAssertEqual(DictatorRecording.state(size: CGSize(width: 28, height: 24), description: nil), .idle,
                       "пара точек сверх квадрата — ещё не часы")
        // Часы записи — живой замер 25.09: 49×24, описания нет.
        XCTAssertEqual(DictatorRecording.state(size: CGSize(width: 49, height: 24), description: nil), .recording)
        XCTAssertEqual(DictatorRecording.state(size: CGSize(width: 49, height: 24), description: ""), .recording)
        // Пауза — по описанию, на всех языках, и даже на квадратной плашке.
        for label in ["Диктовка на паузе", "Dictation paused", "Айтып жазу кідірісте"] {
            XCTAssertEqual(DictatorRecording.state(size: square, description: label), .paused, label)
            XCTAssertEqual(DictatorRecording.state(size: CGSize(width: 40, height: 24), description: " \(label) "),
                           .paused, label)
        }
        // Распознавание — запись уже кончилась, хоть плашка и широкая.
        for label in ["Распознаю…", "Recognizing…", "Танып жатырмын…"] {
            XCTAssertEqual(DictatorRecording.state(size: CGSize(width: 49, height: 24), description: label),
                           .processing, label)
        }
        XCTAssertEqual(DictatorRecording.state(size: .zero, description: nil), .unknown, "пустая рамка — не знаем")
        XCTAssertEqual(DictatorRecording.state(size: nil, description: nil), .unknown)
        XCTAssertTrue(DictatorState.paused.isRecording)
        XCTAssertTrue(DictatorRecording.isRecording(size: CGSize(width: 49, height: 24), description: nil))
        XCTAssertFalse(DictatorState.processing.isRecording)
    }

    // MARK: - решение

    func testDecide() {
        func decide(_ state: DictatorState, _ own: String?, _ key: String, _ age: TimeInterval? = nil)
            -> MicMonitor.Decision {
            MicMonitor.decide(state: state, own: own, key: key, ownAge: age)
        }
        XCTAssertEqual(decide(.idle, nil, "a"), .press(own: "a"))
        XCTAssertEqual(decide(.idle, "b", "a", 10), .press(own: "a"), "записи нет — прежний хозяин не в счёт")
        XCTAssertEqual(decide(.unknown, nil, "a"), .press(own: "a"), "не узнать — по-старому")
        XCTAssertEqual(decide(.processing, "b", "a", 10), .press(own: "a"))
        XCTAssertEqual(decide(.recording, "a", "a"), .press(own: nil), "свой — остановка")
        XCTAssertEqual(decide(.recording, "b", "a"), .refuse)
        XCTAssertEqual(decide(.recording, nil, "a"), .refuse)
        // Пауза: свой — продолжение, хозяин остаётся; чужой — отказ.
        XCTAssertEqual(decide(.paused, "a", "a"), .press(own: "a"))
        XCTAssertEqual(decide(.paused, "b", "a"), .refuse)
        XCTAssertEqual(decide(.paused, nil, "a"), .refuse)
        // Гонка на старте: плашка ещё не догнала своё нажатие.
        XCTAssertEqual(decide(.idle, "b", "a", 0.5), .refuse, "чужой кружок сразу после старта — отказ")
        XCTAssertEqual(decide(.unknown, "b", "a", 1.4), .refuse)
        XCTAssertEqual(decide(.idle, "b", "a", 1.5), .press(own: "a"), "запас кончился — покой правда")
        XCTAssertEqual(decide(.idle, "a", "a", 0.5), .press(own: nil), "свой кружок сразу — остановка")
    }

    // MARK: - нажатия

    func testForeignRecordingRefusesAddressed() {
        let (monitor, box) = rig()
        box.state = .recording  // пишет с F5 в другое окно
        monitor.press(key: "win:11", chat: "local_1", match: "Заказы")
        XCTAssertEqual(box.keys, 0, "клавишу Диктатора не жмём — она остановила бы чужую запись")
        XCTAssertEqual(box.refused.count, 1)
        XCTAssertEqual(box.refused.first?.chat, "local_1", "адрес — чат нажатого окна")
        XCTAssertEqual(box.refused.first?.match, "Заказы", "и его заголовок")
        XCTAssertEqual(box.notices, ["🎙 Сначала останови запись в Диктаторе"])
        XCTAssertEqual(monitor.refusals, 1)
        XCTAssertNil(monitor.ownStart)
        XCTAssertTrue(monitor.status.hasSuffix("/0/0/1"), monitor.status)
    }

    func testOwnRecordingStopsOnSecondPress() {
        let (monitor, box) = rig()
        monitor.press(key: "win:11")
        XCTAssertEqual(box.keys, 1)
        XCTAssertEqual(box.state, .recording)
        XCTAssertEqual(monitor.ownStart, "win:11")
        XCTAssertEqual(monitor.ownAt, box.now)

        // Кружок другого окна, пока пишет первое, — отказ, хозяин прежний.
        later(box, 3)
        monitor.press(key: "win:12")
        XCTAssertEqual(box.keys, 1)
        XCTAssertEqual(box.refused.count, 1)
        XCTAssertEqual(monitor.ownStart, "win:11")

        // Тот же кружок — остановка, как раньше.
        monitor.press(key: "win:11")
        XCTAssertEqual(box.keys, 2)
        XCTAssertEqual(box.state, .idle)
        XCTAssertNil(monitor.ownStart)
        XCTAssertNil(monitor.ownAt)

        // Остановили — теперь второе окно начинает своё.
        later(box, 3)
        monitor.press(key: "win:12")
        XCTAssertEqual(box.keys, 3)
        XCTAssertEqual(monitor.ownStart, "win:12")
    }

    func testPausedOwnPressResumesAndKeepsOwner() {
        let (monitor, box) = rig()
        monitor.press(key: "win:11")
        later(box, 5)
        box.state = .paused  // пауза в самом Диктаторе
        monitor.press(key: "win:12")
        XCTAssertEqual(box.keys, 1, "чужой кружок на паузе — отказ")
        XCTAssertEqual(box.refused.count, 1)
        monitor.press(key: "win:11")
        XCTAssertEqual(box.keys, 2, "свой кружок на паузе — F5, продолжение")
        XCTAssertEqual(monitor.ownStart, "win:11", "хозяин остаётся")
        XCTAssertEqual(box.state, .recording)
    }

    func testStartRaceRefusesForeignWithinGrace() {
        let (monitor, box) = rig()
        monitor.postKey = { box.keys += 1 }  // плашка Диктатора ещё не догнала — всё ещё покой
        monitor.press(key: "win:11")
        later(box, 0.8)
        monitor.press(key: "win:12")
        XCTAssertEqual(box.keys, 1, "меньше 1,5 с после своего старта — считаем записью")
        XCTAssertEqual(box.refused.count, 1)
        XCTAssertEqual(monitor.ownStart, "win:11")
        later(box, 1)
        monitor.press(key: "win:12")
        XCTAssertEqual(box.keys, 2, "запас вышел, Диктатор в покое — жмём, хозяин новый")
        XCTAssertEqual(monitor.ownStart, "win:12")
    }

    // MARK: - хозяин устаревает

    func testOwnerExpiresWhenDictatorIdle() {
        let (monitor, box) = rig()
        monitor.press(key: "win:11")
        XCTAssertEqual(monitor.ownStart, "win:11")
        let asked = box.asked

        // Запас старта — тик Диктатора не спрашивает.
        later(box, 1)
        monitor.tick(titles: [], at: box.now)
        XCTAssertEqual(box.asked, asked)
        XCTAssertEqual(monitor.ownStart, "win:11")

        // Пишет — хозяин на месте.
        later(box, 1)
        monitor.tick(titles: [], at: box.now)
        XCTAssertEqual(box.asked, asked + 1)
        XCTAssertEqual(monitor.ownStart, "win:11")

        // Не чаще раза в 2 с.
        later(box, 1)
        monitor.tick(titles: [], at: box.now)
        XCTAssertEqual(box.asked, asked + 1)

        // Остановили в самом Диктаторе — покой, хозяина нет.
        box.state = .idle
        later(box, 1)
        monitor.tick(titles: [], at: box.now)
        XCTAssertNil(monitor.ownStart)
        XCTAssertNil(monitor.ownAt)

        // Следующая запись с F5 в другое окно — первый кружок больше не хозяин: отказ, а не остановка.
        box.state = .recording
        later(box, 5)
        monitor.press(key: "win:11")
        XCTAssertEqual(box.keys, 1)
        XCTAssertEqual(box.refused.count, 1)

        // Без хозяина тик Диктатора не спрашивает.
        let quiet = box.asked
        later(box, 5)
        monitor.tick(titles: [], at: box.now)
        XCTAssertEqual(box.asked, quiet)
    }

    func testOwnerClearedWhenDictatorQuits() {
        let (monitor, box) = rig()
        monitor.noteDictator(true)
        monitor.press(key: "win:11")
        XCTAssertNotNil(monitor.ownStart)
        monitor.noteDictator(false)
        XCTAssertNil(monitor.ownStart)
        XCTAssertNil(monitor.ownAt)
        XCTAssertEqual(box.keys, 1)
    }

    // MARK: - ключ хозяина — окно

    func testOwnerKeyByWindowID() {
        let at = Date(timeIntervalSince1970: 1_000)
        let page = ChatPage(kind: .popout, chat: "local_1", title: "Ожидание", store: "ok", at: at)
        let twin = ChatPage(kind: .popout, chat: "local_1", title: "Ожидание", store: "ok", at: at)
        let a = MicMonitor.ScreenWindow(pid: 7, frame: .zero, alpha: 1, id: 101)
        let b = MicMonitor.ScreenWindow(pid: 7, frame: .zero, alpha: 1, id: 102)
        XCTAssertEqual(MicMonitor.ownerKey(window: a, page: page), "win:101")
        XCTAssertNotEqual(MicMonitor.ownerKey(window: a, page: page), MicMonitor.ownerKey(window: b, page: twin),
                          "одинаковые заголовок и чат — разные окна")
        // Номера окна нет — по-старому: чат, без него заголовок.
        let none = MicMonitor.ScreenWindow(pid: 7, frame: .zero, alpha: 1)
        XCTAssertEqual(MicMonitor.ownerKey(window: none, page: page), "popout:local_1")
        XCTAssertEqual(MicMonitor.ownerKey(ChatPage(kind: .main, chat: nil, title: "Claude", store: "ok", at: at)),
                       "main:Claude")
    }

    // MARK: - команда `mic-refused` (контракт WF92 (а))

    func testMicRefusedCommandBytes() {
        let id = "1756900000123-0042"
        let at = Date(timeIntervalSince1970: 1_756_900_000)
        XCTAssertEqual(CommandChannel.payload(action: MicMonitor.refusedAction,
                                              fields: MicMonitor.refusedFields(chat: "local_1", match: "Заказы"),
                                              id: id, at: at),
                       "{\"id\":\"1756900000123-0042\",\"action\":\"mic-refused\","
                       + "\"at\":\"2025-09-03T11:46:40Z\",\"reason\":\"recording\","
                       + "\"chat\":\"local_1\",\"match\":\"Заказы\"}")
        XCTAssertEqual(CommandChannel.payload(action: MicMonitor.refusedAction,
                                              fields: MicMonitor.refusedFields(chat: nil, match: "Claude"),
                                              id: id, at: at),
                       "{\"id\":\"1756900000123-0042\",\"action\":\"mic-refused\","
                       + "\"at\":\"2025-09-03T11:46:40Z\",\"reason\":\"recording\","
                       + "\"chat\":null,\"match\":\"Claude\"}")
    }

    // MARK: - К4: край значка (контракт WF92 (б))

    func testMicSpotAnchor() {
        XCTAssertEqual(ChatProbe.micSpot([58, 41, 22, 22]), CGRect(x: 58, y: 41, width: 22, height: 22))
        XCTAssertEqual(ChatProbe.micAnchor([58, 41, 22, 22]), .right, "четыре элемента — старая страница, правый край")
        XCTAssertEqual(ChatProbe.micSpot([30, 41, 22, 22, 1]), CGRect(x: 30, y: 41, width: 22, height: 22))
        XCTAssertEqual(ChatProbe.micAnchor([30, 41, 22, 22, 1]), .left)
        XCTAssertEqual(ChatProbe.micAnchor([58, 41, 22, 22, 0]), .right)
        XCTAssertNil(ChatProbe.micSpot([30, 41, 22, 22, 2]), "чужой край — мусор")
        XCTAssertNil(ChatProbe.micSpot([30, 41, 22, 22, "1"]))
        XCTAssertNil(ChatProbe.micSpot([30, 41, 22, 22, true]))
        XCTAssertNil(ChatProbe.micSpot([30, 41, 22, 22, 0.5]))
        XCTAssertNil(ChatProbe.micSpot([30, 41, 22, 22, 1, 0]))
    }

    func testMicRectFromLeftEdge() {
        let window = CGRect(x: 100, y: 50, width: 500, height: 800)
        let spot = CGRect(x: 30, y: 41, width: 22, height: 22)
        XCTAssertEqual(MicMonitor.micRect(spot: spot, window: window, anchor: .left),
                       CGRect(x: 130, y: 809, width: 22, height: 22))
        XCTAssertEqual(MicMonitor.micRect(spot: spot, window: window, anchor: .right),
                       CGRect(x: 570, y: 809, width: 22, height: 22))
        XCTAssertEqual(MicMonitor.micRect(spot: spot, window: window), MicMonitor.micRect(spot: spot, window: window,
                                                                                         anchor: .right))
    }

    func testParsedPageCarriesAnchor() throws {
        let body: [String: Any] = ["at": "x", "results": [["id": 1, "source": ProbeSourceFixture.metadata(url: "https://claude.ai/epitaxy"), "url": "https://claude.ai/epitaxy",
            "result": ["v": 1, "nonce": "n1", "kind": "main", "title": "Claude", "store": "ok",
                       "mic": [30, 41, 22, 22, 1]] as [String: Any]]]]
        let page = try XCTUnwrap(ChatProbe.parseAnswer(try JSONSerialization.data(withJSONObject: body), nonce: "n1",
                                                        at: Date()).pages.first)
        XCTAssertEqual(page.mic, CGRect(x: 30, y: 41, width: 22, height: 22))
        XCTAssertEqual(page.micAnchor, .left)
    }

    // MARK: - карта раз в 5 с (контракт WF92 (в))

    func testProbeFastWhileDictatorMicVisible() throws {
        var now = Date(timeIntervalSince1970: 1_757_100_000)
        var script: String?
        var scriptVersion = 0
        var result: Data?
        var resultVersion = 0
        var writes = 0
        let files = ChatProbeFiles(
            scriptInfo: { script == nil ? nil : ("\(scriptVersion)", now) },
            readScript: { script },
            writeScript: { text in script = text; scriptVersion += 1; writes += 1; return true },
            resultInfo: { result == nil ? nil : "\(resultVersion)" },
            readResult: { result })
        let probe = ChatProbe(files: files, now: { now }, random: { 1 })
        var fast = false
        probe.isEnabled = { false }
        probe.isMicWanted = { true }
        probe.isMicFast = { fast }
        let windows: [(title: String, frame: CGRect?)] = [(title: "Claude", frame: nil)]
        func answer() throws {
            let nonce = try XCTUnwrap(script.flatMap { ChatProbe.markNonce($0) })
            let page: [String: Any] = ["v": 1, "nonce": nonce, "kind": "main", "title": "Claude", "store": "ok",
                                       "frame": [0, 25, 500, 800], "mic": [58, 41, 22, 22]]
            result = try JSONSerialization.data(withJSONObject: ["at": "x", "results": [["id": 1,
                "source": ProbeSourceFixture.metadata(url: "https://claude.ai/epitaxy"), "url": "https://claude.ai/epitaxy", "result": page]]])
            resultVersion += 1
        }
        probe.tick(windows: windows, indexRevision: 1)
        XCTAssertEqual(writes, 1)
        try answer()
        now = now.addingTimeInterval(6)
        probe.tick(windows: windows, indexRevision: 1)
        XCTAssertEqual(writes, 1, "режим claude — пол 15 с")

        fast = true
        try answer()
        now = now.addingTimeInterval(2)
        probe.tick(windows: windows, indexRevision: 1)
        XCTAssertEqual(writes, 2, "dictator и значок виден — раз в 5 с")
        try answer()
        now = now.addingTimeInterval(4)
        probe.tick(windows: windows, indexRevision: 1)
        XCTAssertEqual(writes, 2, "не чаще 5 с")
        try answer()
        now = now.addingTimeInterval(1)
        probe.tick(windows: windows, indexRevision: 1)
        XCTAssertEqual(writes, 3)
    }

    func testWantsFastPagesOnlyInDictatorWithMic() {
        let monitor = MicMonitor()
        let at = Date(timeIntervalSince1970: 1_000)
        var pages = [ChatPage(kind: .main, chat: nil, title: "Claude", store: "ok", mic: nil, at: at)]
        monitor.pages = { pages }
        monitor.noteDictator(true)
        XCTAssertFalse(monitor.wantsFastPages, "значка не видно")
        pages = [ChatPage(kind: .main, chat: nil, title: "Claude", store: "ok",
                          mic: CGRect(x: 58, y: 41, width: 22, height: 22), at: at)]
        XCTAssertTrue(monitor.wantsFastPages)
        monitor.noteDictator(false)
        XCTAssertFalse(monitor.wantsFastPages, "режим claude — по-старому")
    }
}
