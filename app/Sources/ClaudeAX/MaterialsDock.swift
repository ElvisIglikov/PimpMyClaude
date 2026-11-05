import CoreGraphics
import Foundation

/// Панель материалов слева внутри окна Claude (WF277, #10644; контракт `docs/contracts/560-wf277-dock.md`): страница
/// шлёт место панели внутри окна (`/dock`, К-DOCK-1), Пимп находит CGWindowID окна Claude по его рамке и передаёт
/// PimpViewer (К-DOCK-2) — та держит над местом своё окно-док и сама следит за окном Claude.
///
/// Последний выигрывает: к PimpViewer в полёте не больше одного запроса и один отложенный — свежая рамка заменяет
/// отложенную, ответ странице приходит по последней. Сердце раз в 2 с, пока страница шлёт; тишина владельца 8 с —
/// `on=0`, но не на паузе (`vis=0`: скрытая страница шлёт редко). Владелец дока — окно (CGWindowID по рамке
/// `wx..wh`, не `chat`: у чата без id он nil у всех), приславшее `on=1` с `vis=1` последним; повтор сердца чужого
/// окна (то же место, та же рамка) док не отнимает — иначе два главных окна с нажатой кнопкой перетягивали бы его раз
/// в 2 с. `on=0` снимает док только у владельца; `probe=1` — жив ли PimpViewer, ему ничего не шлётся.
///
/// Всё состояние — на своей очереди; порт и клиент галереи ответа не ждут.
public final class MaterialsDock {
    /// Место панели относительно левого верхнего угла окна и рамка окна (точки, начало — верх-лево главного экрана).
    public struct Place: Equatable {
        public let place: CGRect
        public let window: CGRect
        /// Строка «Файлы» над местом (#11654, К-DOCK-6): годная по К-DOCK-6b, иначе nil.
        public var bar: Bar? = nil
    }

    /// Строка «Файлы» (К-DOCK-6a): `x` — левый край полосы (`bx`, не левее места), `y` и `h` — кнопка «Файлы»; точки окна.
    public struct Bar: Equatable {
        public let x: Int
        public let y: Int
        public let h: Int
    }

    /// Запрос страницы `/dock` (К-DOCK-1); `on=0` — без места, с рамкой окна (`window`, нет или мусор — nil);
    /// `probe` — `probe=1`, жив ли PimpViewer.
    public struct Request: Equatable {
        public let on: Bool
        public let vis: Bool
        public let place: Place?
        public let chat: String?
        public var window: CGRect? = nil
        public var probe = false
        /// Цвет боковой панели Claude под доком (#10759, К-DOCK-5): `bg` — 6 hex, иначе nil.
        public var bg: String? = nil
    }

    /// Окно Claude и место в нём — то, что уходит PimpViewer (`win&x&y&w&h`).
    public struct Spot: Equatable {
        public let window: CGWindowID
        public let place: CGRect
        /// Фон страницы дока — цвет боковой панели Claude (К-DOCK-5), 6 hex.
        public var bg: String? = nil
        /// Строка «Файлы» (К-DOCK-6c), только годная.
        public var bar: Bar? = nil

        /// `&win=…&x=…&y=…&w=…&h=…` (+ `&bg=…`, + `&bx=…&by=…&bh=…`) — одно на `/dock` и `/accept … dock=1`.
        var query: String {
            "&win=\(window)&x=\(Int(place.minX))&y=\(Int(place.minY))&w=\(Int(place.width))&h=\(Int(place.height))"
                + (bg.map { "&bg=\($0)" } ?? "") + (bar.map { "&bx=\($0.x)&by=\($0.y)&bh=\($0.h)" } ?? "")
        }
    }

    /// Запрос К-DOCK-2: `on=1` — со `spot`, `on=0` — без.
    public struct Command: Equatable {
        public let vis: Bool
        public let spot: Spot?
        static let off = Command(vis: false, spot: nil)
    }

    public enum Viewer: String { case up, down, none }

    /// Ответ PimpViewer: `up` — ответила 200, `none` — не установлена, иначе `down` (молчит или старая без дока).
    public struct Reply: Equatable {
        public let viewer: Viewer
        public let docked: Bool
    }

    /// Ответ странице `{ok, viewer, docked, owner}`. `ok` — запрос годен и окно нашлось.
    public struct Answer: Equatable {
        public let ok: Bool
        public let viewer: Viewer
        public let docked: Bool
        /// Док у этого окна (или ничей) — `owner:"this"`, у другого — `"other"`.
        public let mine: Bool
        /// Ответ на `probe=1` — только `{ok, viewer}` (+ `apart`).
        public var probe = false
        /// #11677: PimpViewer `up`, дока нет ни у одного окна, отдельное окно галереи на экране — файл из чата странице
        /// открывать там, док сам не ставить. Старая страница поле не читает.
        public var apart = false
        /// PimpViewer не ответил за `HtmlChromeOpener.dockReplyWait`.
        static let late = Answer(ok: false, viewer: .down, docked: false, mine: true)

        var json: Data {
            if probe { return Data(#"{"ok":\#(ok),"viewer":"\#(viewer.rawValue)","apart":\#(apart)}"#.utf8) }
            return Data(#"{"ok":\#(ok),"viewer":"\#(viewer.rawValue)","docked":\#(docked),"owner":"\#(mine ? "this" : "other")","apart":\#(apart)}"#.utf8)
        }
    }

    static let heartInterval: TimeInterval = 2
    /// Тишина видимого владельца — `on=0`; у PimpViewer своя — 10 с, док не кончается раньше этой.
    static let silence: TimeInterval = 8
    /// Рамка окна из страницы и из CGWindowList сходятся с этим допуском, точки.
    static let tolerance: CGFloat = 2
    /// Найденный CGWindowID той же рамки верен столько — тяга рейки (кадр за кадром) не обходит список окон.
    static let windowCache: TimeInterval = 2

    /// Запрос PimpViewer (К-DOCK-2); `done` — ровно раз, с любой очереди. Боевой — `ViewerClient.dock`.
    var send: (Command, @escaping (Reply) -> Void) -> Void = { _, done in done(Reply(viewer: .down, docked: false)) }
    /// CGWindowID окна Claude с этой рамкой (тест подменяет).
    var findWindow: (CGRect) -> CGWindowID? = MaterialsDock.claudeWindow(frame:)
    /// `probe=1`: жив ли PimpViewer — без запроса к нему (`done` — раз, с любой очереди). Боевой — `ViewerClient.dockProbe`.
    var probe: (@escaping (Viewer) -> Void) -> Void = { $0(.down) }
    /// Отдельное окно галереи на экране (#11677; боевой — `ViewerClient.windowShown`). Зовут на очереди дока и только
    /// когда дока нет: окно-док — тоже окно PimpViewer на экране.
    var windowShown: () -> Bool = { false }
    var now: () -> Date = Date.init
    /// Своё сердце таймером; тесты зовут `tick()` сами.
    var heartTimer = true

    private let queue = DispatchQueue(label: "pimpmyclaude.materials-dock", qos: .userInitiated)
    private struct Owner {
        let window: CGWindowID
        let spot: Spot
        let vis: Bool
    }
    private struct Batch {
        var command: Command
        var replies: [(Reply) -> Void]
    }
    private var owner: Owner?
    private var ownerAt: Date?
    /// Последнее от каждого окна — повтор от новости (смены места, рамки, `vis`).
    private var seen: [CGWindowID: (place: Place, vis: Bool, at: Date)] = [:]
    private var found: (frame: CGRect, window: CGWindowID, at: Date)?
    private var inFlight = false
    private var pending: Batch?
    private var sentAt: Date?
    private var viewer: Viewer = .down
    private var docked = false
    private var heart: DispatchSourceTimer?

    public init() {}

    /// Дождаться очереди дока — тестам.
    func drain() { queue.sync {} }

    // MARK: - страница

    /// `/dock` страницы. `reply` — ровно раз, на очереди дока.
    public func handle(_ request: Request, reply: @escaping (Answer) -> Void) {
        if request.probe {
            return probe { [self] viewer in
                queue.async { [self] in
                    reply(Answer(ok: true, viewer: viewer, docked: false, mine: true, probe: true, apart: apart(viewer)))
                }
            }
        }
        queue.async { [self] in
            if request.on, let place = request.place { return handleOn(request, place, reply) }
            handleOff(request.window, reply)
        }
    }

    /// `/open-html … dock=1`: окно нашлось — оно владелец дока (клик человека), `done(spot)` для `/accept … dock=1`;
    /// не нашлось — `done(nil)`. На очереди дока.
    public func open(_ place: Place, done: @escaping (Spot?) -> Void) {
        queue.async { [self] in
            guard let window = resolve(place.window) else { return done(nil) }
            let spot = Spot(window: window, place: place.place, bar: place.bar)
            seen[window] = (place, true, now())
            take(Owner(window: window, spot: spot, vis: true))
            done(spot)
        }
    }

    /// Сердце: раз в 2 с повторить место, если с прошлого запроса прошло ≥ 1,5 с; видимый владелец молчит 8 с — `on=0`.
    func tick() {
        queue.async { [self] in beat() }
    }

    private func handleOn(_ request: Request, _ place: Place, _ reply: @escaping (Answer) -> Void) {
        guard let window = resolve(place.window) else {
            return reply(Answer(ok: false, viewer: viewer, docked: docked, mine: isMine(nil, frame: place.window), apart: apart(viewer)))
        }
        let at = now()
        seen = seen.filter { at.timeIntervalSince($0.value.at) < Self.silence * 2 }
        let previous = seen[window]
        seen[window] = (place, request.vis, at)
        let news = previous == nil || previous?.place != place || previous?.vis != request.vis
        let claims = owner == nil || owner?.window == window || (request.vis && (news || owner?.vis == false))
        guard claims else { return reply(Answer(ok: true, viewer: viewer, docked: docked, mine: false, apart: apart(viewer))) }
        let spot = Spot(window: window, place: place.place, bg: request.bg, bar: place.bar)
        take(Owner(window: window, spot: spot, vis: request.vis))
        submit(Command(vis: request.vis, spot: spot)) { [self] in reply(answer($0, window)) }
    }

    /// `on=0` — закрыл человек: снимает док только владелец (по окну `wx..wh`) или когда дока нет. Не владелец — его
    /// прежнее место забыто: следующее нажатие этого окна — новость и забирает док.
    private func handleOff(_ frame: CGRect?, _ reply: @escaping (Answer) -> Void) {
        let window = frame.flatMap(resolve)
        guard isMine(window, frame: frame) else {
            if let window = window { seen[window] = nil }
            return reply(Answer(ok: true, viewer: viewer, docked: docked, mine: false, apart: apart(viewer)))
        }
        drop()
        submit(.off) { [self] in reply(answer($0, window)) }
    }

    private func answer(_ reply: Reply, _ window: CGWindowID?) -> Answer {
        Answer(ok: true, viewer: reply.viewer, docked: reply.docked, mine: isMine(window, frame: nil), apart: apart(reply.viewer))
    }

    /// #11677: галерея жива, дока нет (ни владельца, ни `docked` в последнем ответе) и её окно на экране.
    private func apart(_ viewer: Viewer) -> Bool {
        viewer == .up && owner == nil && !docked && windowShown()
    }

    /// Док у этого окна или ничей. Окно не нашлось — по рамке, с которой владелец приходил последним; рамки нет —
    /// не владелец.
    private func isMine(_ window: CGWindowID?, frame: CGRect?) -> Bool {
        guard let owner = owner else { return true }
        if let window = window { return owner.window == window }
        guard let frame = frame, let known = seen[owner.window]?.place.window else { return false }
        return known == frame
    }

    private func take(_ next: Owner) {
        owner = next
        ownerAt = now()
        startHeart()
    }

    private func drop() {
        owner = nil
        ownerAt = nil
        heart?.cancel()
        heart = nil
    }

    private func beat() {
        guard let owner = owner, let ownerAt = ownerAt else { return drop() }
        let at = now()
        if owner.vis, at.timeIntervalSince(ownerAt) >= Self.silence {
            drop()
            return submit(.off, nil)
        }
        guard at.timeIntervalSince(sentAt ?? .distantPast) >= Self.heartInterval - 0.5 else { return }
        submit(Command(vis: owner.vis, spot: owner.spot), nil)
    }

    private func startHeart() {
        guard heartTimer, heart == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.heartInterval, repeating: Self.heartInterval)
        timer.setEventHandler { [weak self] in self?.beat() }
        timer.resume()
        heart = timer
    }

    // MARK: - последний выигрывает

    private func submit(_ command: Command, _ reply: ((Reply) -> Void)?) {
        guard inFlight else { return fly(Batch(command: command, replies: reply.map { [$0] } ?? [])) }
        var next = pending ?? Batch(command: command, replies: [])
        next.command = command
        if let reply = reply { next.replies.append(reply) }
        pending = next
    }

    private func fly(_ batch: Batch) {
        inFlight = true
        sentAt = now()
        send(batch.command) { [weak self] reply in
            guard let self = self else { return }
            self.queue.async {
                self.viewer = reply.viewer
                self.docked = reply.docked
                batch.replies.forEach { $0(reply) }
                self.inFlight = false
                if let next = self.pending {
                    self.pending = nil
                    self.fly(next)
                }
            }
        }
    }

    // MARK: - окно Claude

    private func resolve(_ frame: CGRect) -> CGWindowID? {
        let at = now()
        if let found = found, found.frame == frame, at.timeIntervalSince(found.at) < Self.windowCache, at >= found.at {
            return found.window
        }
        found = nil
        guard let window = findWindow(frame) else { return nil }
        found = (frame, window, at)
        return window
    }

    /// Все окна, и за экраном тоже (другой стол), без рабочего стола; только Quartz — без AX и записи экрана.
    static func claudeWindow(frame: CGRect) -> CGWindowID? {
        guard let list = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        return windowID(in: list, frame: frame)
    }

    /// Окно Claude обычного слоя с рамкой `frame` ±`tolerance`: видимое на экране — первое сверху, иначе первое любое.
    /// Чистая, её гоняют тесты.
    static func windowID(in list: [[String: Any]], frame: CGRect, tolerance: CGFloat = MaterialsDock.tolerance) -> CGWindowID? {
        var hidden: CGWindowID?
        for info in list {
            guard info[kCGWindowOwnerName as String] as? String == "Claude",
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  abs(rect.minX - frame.minX) <= tolerance, abs(rect.minY - frame.minY) <= tolerance,
                  abs(rect.width - frame.width) <= tolerance, abs(rect.height - frame.height) <= tolerance
            else { continue }
            if (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true { return number }
            if hidden == nil { hidden = number }
        }
        return hidden
    }

    // MARK: - разбор К-DOCK-1

    /// `GET /dock?on=1&vis=<0|1>&x&y&w&h&wx&wy&ww&wh[&bx&by&bh]&chat&seq` | `GET /dock?on=0&chat&wx&wy&ww&wh&seq` |
    /// `GET /dock?probe=1` → запрос; негодный — nil. `chat` мусорный — nil, запрос годен; рамка `on=0` негодна — nil,
    /// запрос годен; `seq` не нужен: порядок — порядок прихода. Чистая.
    public static func parse(_ head: String) -> Request? {
        guard let components = HtmlChromeOpener.query(head, path: "/dock") else { return nil }
        let items = components.queryItems ?? []
        let value = { (name: String) in items.first(where: { $0.name == name })?.value }
        let chat = HtmlChromeOpener.chatID(value("chat"))
        if value("probe") == "1" { return Request(on: false, vis: false, place: nil, chat: chat, probe: true) }
        switch value("on") {
        case "0":
            return Request(on: false, vis: false, place: nil, chat: chat, window: frame(value))
        case "1":
            guard let vis = ["0": false, "1": true][value("vis") ?? ""], let place = place(value) else { return nil }
            return Request(on: true, vis: vis, place: place, chat: chat, bg: HtmlChromeOpener.color(value("bg")))
        default:
            return nil
        }
    }

    /// `wx,wy,ww,wh` — рамка окна: целые до 6 знаков, размеры > 0; иначе nil.
    static func frame(_ value: (String) -> String?) -> CGRect? {
        let numbers = ["wx", "wy", "ww", "wh"].compactMap { name -> Int? in
            guard let text = value(name), text.range(of: "^-?[0-9]{1,6}$", options: .regularExpression) != nil
            else { return nil }
            return Int(text)
        }
        guard numbers.count == 4, numbers[2] > 0, numbers[3] > 0 else { return nil }
        return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    }

    /// `x,y,w,h` (место в окне) и `wx,wy,ww,wh` (рамка окна) — целые до 6 знаков; место — внутри окна (±2), размеры > 0.
    static func place(_ value: (String) -> String?) -> Place? {
        let numbers = ["x", "y", "w", "h", "wx", "wy", "ww", "wh"].compactMap { name -> Int? in
            guard let text = value(name), text.range(of: "^-?[0-9]{1,6}$", options: .regularExpression) != nil
            else { return nil }
            return Int(text)
        }
        guard numbers.count == 8 else { return nil }
        let (x, y, w, h, ww, wh) = (numbers[0], numbers[1], numbers[2], numbers[3], numbers[6], numbers[7])
        let slack = Int(tolerance)
        guard x >= 0, y >= 0, w > 0, h > 0, ww > 0, wh > 0, x + w <= ww + slack, y + h <= wh + slack else { return nil }
        return Place(place: CGRect(x: x, y: y, width: w, height: h),
                     window: CGRect(x: numbers[4], y: numbers[5], width: ww, height: wh), bar: bar(value, x: x, y: y, w: w))
    }

    /// `bx,by,bh` — строка «Файлы» (К-DOCK-6b): целые до 6 знаков, `by ≥ 0`, `16 ≤ bh ≤ 64`, `by + bh ≤ y`; `bx < x` →
    /// `bx = x`; `bx ≤ x + w − 80`. Негодно или нет ключа — nil, место годно.
    static func bar(_ value: (String) -> String?, x: Int, y: Int, w: Int) -> Bar? {
        let numbers = ["bx", "by", "bh"].compactMap { name -> Int? in
            guard let text = value(name), text.range(of: "^-?[0-9]{1,6}$", options: .regularExpression) != nil
            else { return nil }
            return Int(text)
        }
        guard numbers.count == 3 else { return nil }
        let (bx, by, bh) = (max(numbers[0], x), numbers[1], numbers[2])
        guard by >= 0, (16...64).contains(bh), by + bh <= y, bx <= x + w - 80 else { return nil }
        return Bar(x: bx, y: by, h: bh)
    }
}

extension HtmlChromeOpener {
    /// `200 {ok, viewer, docked, owner}` на `/dock`; CORS — как у остальных ручек страницы.
    static func dockResponse(_ answer: MaterialsDock.Answer, access: PageAccess) -> Data {
        httpResponse(status: 200, contentType: "application/json; charset=utf-8", body: answer.json, access: access)
    }

    /// `200 {taken, opened}` на `/open-html … dock=1` — когда PimpViewer ответил; файла нет — `404` с тем же телом (WF288).
    static func dockOpenResponse(taken: Bool, opened: Bool, access: PageAccess, status: Int = 200) -> Data {
        httpResponse(status: status, contentType: "application/json; charset=utf-8",
                     body: Data(#"{"taken":\#(taken),"opened":\#(opened)}"#.utf8), access: access)
    }
}

extension ClaudeAXController {
    /// Док материалов (WF277): ручки порта → `materialsDock` → PimpViewer. Зовут из `start()`.
    func connectMaterialsDock() {
        materialsDock.send = { [weak self] command, done in
            guard let self = self else { return done(MaterialsDock.Reply(viewer: .down, docked: false)) }
            self.viewerClient.dock(command, done: done)
        }
        materialsDock.probe = { [weak self] done in
            guard let self = self else { return done(.down) }
            self.viewerClient.dockProbe(done: done)
        }
        materialsDock.windowShown = { [weak self] in self?.viewerClient.windowShown() ?? false }
        htmlOpener.onDock = { [weak self] request, reply in
            guard let self = self else { return reply(.late) }
            self.materialsDock.handle(request, reply: reply)
        }
        htmlOpener.toDock = { [weak self] request, done in
            guard let self = self, let place = request.dock else { return done(false, false) }
            self.materialsDock.open(place) { [weak self] spot in
                guard let self = self else { return done(false, false) }
                // Окна с такой рамкой нет — прежний клик в галерею.
                guard let spot = spot else {
                    return self.viewerClient.accept(path: request.path, mode: .click, chat: request.chat) { done($0, $0) }
                }
                self.viewerClient.accept(path: request.path, chat: request.chat, dock: spot, done: done)
            }
        }
    }
}
