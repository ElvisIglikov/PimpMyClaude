import AppKit
import Foundation
import Patcher

// Терминалы всегда на экране (#10564, слово Элвиса 22.10.2026 ~13:00: «Лучше бы они открытыми были. Можно их сделать
// открытыми всегда и заголовки чатов там в терминалах как-то чтоб были, чтоб я всегда понимал, какой терминал по
// какому проекту работает»). Раз в `interval` приложение смотрит живые сессии tmux `rick-<проект>`: у сессии нет окна
// Terminal — открывает его (`tmux attach`, Terminal не выводится вперёд — фокус у человека не отнимаем); окно свёрнуто
// в Dock — разворачивает; заголовок — имя проекта без значков (`PanelTerminals.retitle`). Каждой сессии — один раз за
// её жизнь (`session_created`), и через перезапуск Пимпа тоже: закрыл или свернул окно человек — его выбор до новой сессии. Окна не
// двигаются и размер не меняют. Terminal не запущен или права управлять им нет — ничего (сами его не запускаем).

public final class TerminalKeeper {
    /// Шаг проверки, с.
    public static let interval: TimeInterval = 10

    /// Живая сессия: имя после `rick-`, когда заведена (с эпохи), tty подключённых клиентов.
    public struct Session: Equatable {
        public let name: String
        public let created: Int
        public let clients: [String]

        public init(name: String, created: Int, clients: [String]) {
            self.name = name
            self.created = created
            self.clients = clients
        }

        var key: String { "\(name)@\(created)" }
    }

    /// Что сделать с сессией: окна нет — открыть; окно есть — развернуть свёрнутое.
    public enum Step: Equatable {
        case open(String)
        case unminimize(String, [String])
    }

    /// Сессии, которые уже показывали (`Session.key`); помнятся и через перезапуск Пимпа — новая версия не
    /// разворачивает окна, которые человек свернул.
    private(set) var handled: Set<String>
    private let defaults: UserDefaults?
    static let handledKey = "terminalKeeperHandled10564"
    private var busy = false
    private let queue = DispatchQueue(label: "pimp.terminal-keeper", qos: .utility)

    public init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        handled = Set(defaults?.stringArray(forKey: Self.handledKey) ?? [])
    }

    /// Шаги для новых сессий; показанные запоминаются. Исчезнувшие сессии из памяти уходят.
    func steps(_ sessions: [Session]) -> [Step] {
        let before = handled
        handled.formIntersection(sessions.map { $0.key })
        var out: [Step] = []
        for session in sessions.sorted(by: { $0.name.lowercased() < $1.name.lowercased() })
        where !handled.contains(session.key) {
            handled.insert(session.key)
            out.append(session.clients.isEmpty ? .open(session.name) : .unminimize(session.name, session.clients))
        }
        if handled != before { defaults?.set(handled.sorted(), forKey: Self.handledKey) }
        return out
    }

    /// Разбор `tmux ls -F '#{session_name}⇥#{session_created}'` и `list-clients -F '#{client_tty}⇥#{session_name}'`.
    static func sessions(ls: String, clients: String) -> [Session] {
        var ttys: [String: [String]] = [:]
        for line in clients.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: "\t")
            guard parts.count == 2, parts[0].hasPrefix("/dev/") else { continue }
            ttys[parts[1], default: []].append(parts[0])
        }
        return ls.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count == 2, parts[0].hasPrefix("rick-"), parts[0].count > 5,
                  let created = Int(parts[1].trimmingCharacters(in: .whitespaces)) else { return nil }
            return Session(name: String(parts[0].dropFirst(5)), created: created, clients: ttys[parts[0]] ?? [])
        }
    }

    /// Один шаг в фоне; прошлый не кончился — пропуск.
    public func tick() {
        queue.async { [self] in
            guard !busy else { return }
            busy = true
            defer { busy = false }
            run()
        }
    }

    private func run() {
        guard let tmux = PanelTiles.tmuxPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }),
              let ls = FlowShell.run(tmux, ["ls", "-F", "#{session_name}\t#{session_created}"]), ls.status == 0
        else { return }
        if ITermHub.present(ls: ls.text) {
            if defaults?.bool(forKey: ITermHub.modeKey) != true { defaults?.set(true, forKey: ITermHub.modeKey) }
            return runHub(tmux)
        }
        // Режим iTerm уже выбран, а hub нет (перезагрузка Мака, 23.10.2026: сервер tmux поднялся заново, чаты — без
        // окон): завести hub без окна — чаты свяжутся вкладками на следующем шаге. Окно iTerm Пимп сам не открывает
        // (#11016, слово Элвиса 28.10: «постоянно … на передний план вылетает») — только нажатие строки «Терминалов»
        // или `pimp.py term --show`. Терминал macOS не открываем.
        if defaults?.bool(forKey: ITermHub.modeKey) == true, ITermHub.installed {
            guard !Self.sessions(ls: ls.text, clients: "").isEmpty else { return }
            _ = FlowShell.run(tmux, ["new-session", "-d", "-s", ITermHub.session, "-n", ITermHub.placeholder])
            return
        }
        guard PanelTerminals.access(ask: false) == .allowed else { return }
        let clients = FlowShell.run(tmux, ["list-clients", "-F", "#{client_tty}\t#{session_name}"])
        let todo = steps(Self.sessions(ls: ls.text, clients: clients?.status == 0 ? clients?.text ?? "" : ""))
        guard !todo.isEmpty else { return }
        let root = StatusFeed.projectsRoot()
        for step in todo {
            switch step {
            case .open(let name):
                let terminal = PanelTerminal(session: name, title: PanelTerminals.title(session: name, root: root),
                                             turning: false)
                PanelTerminals.retitle([terminal])
                let attach = "exec \(tmux) attach -t '=rick-\(name)'"
                _ = PanelTerminals.osascript(Self.openScript, [terminal.title, attach], timeout: 10)
            case .unminimize(let name, let ttys):
                PanelTerminals.retitle([PanelTerminal(session: name, title: PanelTerminals.title(session: name, root: root),
                                                      turning: false)])
                _ = PanelTerminals.osascript(Self.unminimizeScript, [ttys.joined(separator: "\n")], timeout: 10)
            }
        }
    }

    /// Режим iTerm2: окна чатов — в сводной сессии, мёртвые чаты из неё — вон. Окно iTerm сами не открываем и вперёд
    /// не выводим (#11016): новые вкладки iTerm заводит в фоне (`ensureBackgroundTabs`). Только команды tmux, без
    /// AppleEvents.
    private func runHub(_ tmux: String) {
        guard let list = FlowShell.run(tmux, ["list-windows", "-a", "-F", ITermHub.windowsFormat]), list.status == 0
        else { return }
        _ = ITermHub.ensureCommand(tmux: tmux)
        ITermHub.ensureProfile()
        ITermHub.ensureBackgroundTabs()
        let windows = ITermHub.windows(list.text)
        var plan = ITermHub.plan(windows)
        // Новое окно в hub будит спрятанный iTerm: окно мигает, пока ITermQuiet его не спрячет (#11403, опыт 31.10 18:51 —
        // три из трёх; переименование и закрытие вкладок — нет). iTerm держит hub и не активен — вкладки новых чатов ждут,
        // пока человек его откроет: активация iTerm — шаг сразу (`ITermQuiet.activated`), строка «Терминалов» — `show`.
        if !plan.link.isEmpty, ITermHub.controlled(tmux: tmux), !ITermHub.active {
            plan = ITermHub.plan(windows, link: false)
        }
        let hub = "=" + ITermHub.session + ":"
        for id in plan.mark { _ = FlowShell.run(tmux, ["set-option", "-w", "-t", id, ITermHub.chatOption, "1"]) }
        if plan.placeholder {
            _ = FlowShell.run(tmux, ["new-window", "-d", "-t", hub, "-n", ITermHub.placeholder])
        }
        let root = StatusFeed.projectsRoot()
        for window in plan.link {
            let name = String(window.session.dropFirst(5))
            ITermHub.link(tmux: tmux, session: name, window: window.id,
                          title: PanelTerminals.title(session: name, root: root))
        }
        for id in plan.kill { _ = FlowShell.run(tmux, ["kill-window", "-t", hub + id]) }
        // Вкладка — имя проекта: окна, связанные hub.command после перезагрузки, tmux назвал по программе («claude»).
        let linked = Set(plan.link.map(\.id))
        for (window, title) in ITermHub.renames(windows, title: { PanelTerminals.title(session: $0, root: root) })
        where !linked.contains(window.id) {
            ITermHub.retitle(tmux: tmux, session: String(window.session.dropFirst(5)), window: window.id, title: title)
        }
    }

    /// argv: заголовок, команда подключения. Без `activate`: Terminal вперёд не выходит.
    static let openScript = """
    on run argv
      tell application "Terminal"
        set t to do script (item 2 of argv)
        try
          set current settings of t to settings set "Пимп"
        end try
        set custom title of t to (item 1 of argv)
        set title displays custom title of t to true
        try
          set title displays device name of t to false
          set title displays shell path of t to false
          set title displays window size of t to false
          set title displays file name of t to false
        end try
      end tell
      return "opened"
    end run
    """

    /// argv: tty клиентов строками. Только разворачивает: место и размер окна — как были.
    static let unminimizeScript = """
    on run argv
      if application "Terminal" is not running then return "0"
      set ttys to paragraphs of (item 1 of argv)
      set done to 0
      tell application "Terminal"
        repeat with w in windows
          try
            if miniaturized of w then
              repeat with t in tabs of w
                if ttys contains (tty of t) then
                  set miniaturized of w to false
                  set done to done + 1
                  exit repeat
                end if
              end repeat
            end if
          end try
        end repeat
      end tell
      return done as text
    end run
    """
}

// Сводное окно iTerm2 (#10564, слово Элвиса 22.10.2026 14:50: «он мне нравится визуально… Я бы его лучше использовал,
// чем стандартный»). Есть сессия tmux `pimp-hub` — терминальные чаты живут вкладками одного окна iTerm: окно каждой
// сессии `rick-<проект>` связано в hub (`link-window`, чат один, клиентов два), iTerm держит hub через `tmux -CC`.
// Ловушка: Рик меняет чат через kill-session + new-session того же имени — окно, связанное с hub, не умирает и старый
// claude живёт дальше; такие окна Пимп убивает. Убивает только окна чатов — с опцией окна `@pimp-chat` (опция окна общая
// для всех сессий, где оно связано): вкладка, открытая человеком (⌘T в окне `tmux -CC`), — тоже окно hub, но без
// метки, её не трогаем. Нет `pimp-hub` — прежний Terminal.
public enum ITermHub {
    public static let session = "pimp-hub"
    /// Окно-заглушка: последнее окно hub не убиваем — с ним умерла бы сама сессия и режим iTerm.
    static let placeholder = "pimp-hub-start"
    static let bundle = "com.googlecode.iterm2"
    static let places = ["/Applications/iTerm.app", NSHomeDirectory() + "/Applications/iTerm.app"]
    /// Метка окна чата: ставит Пимп (и `hub.command`) окнам `rick-*`; по ней — и только по ней — окно hub убивается.
    static let chatOption = "@pimp-chat"
    /// Режим iTerm выбран (hub видели хоть раз): без hub Пимп открывает hub.command, а не окна Терминала.
    static let modeKey = "terminalKeeperITermHub10564"
    static let windowsFormat = "#{session_name}\t#{window_id}\t#{@pimp-chat}\t#{window_name}"
    static var commandFile: URL { SupportFiles.directory.appendingPathComponent("iterm/hub.command") }
    static var installed: Bool { places.contains { FileManager.default.fileExists(atPath: $0) } }
    /// iTerm — активное приложение (человек в нём).
    static var active: Bool { NSRunningApplication.runningApplications(withBundleIdentifier: bundle).contains { $0.isActive } }

    /// Окно tmux в сессии (`list-windows -a`): связанное окно видно в каждой своей сессии.
    struct Window: Equatable {
        let session: String
        let id: String
        /// Есть метка `@pimp-chat`.
        let chat: Bool
        let name: String
    }

    /// Что сделать с hub: пометить окна чатов, завести заглушку, связать окна чатов, убить окна умерших чатов.
    struct Plan: Equatable {
        var mark: [String] = []
        var placeholder = false
        var link: [Window] = []
        var kill: [String] = []
    }

    static func present(ls: String) -> Bool {
        ls.components(separatedBy: "\n").contains { $0.components(separatedBy: "\t").first == session }
    }

    static func windows(_ text: String) -> [Window] {
        text.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 4, !parts[0].isEmpty, parts[1].hasPrefix("@") else { return nil }
            return Window(session: parts[0], id: parts[1], chat: parts[2] == "1",
                          name: parts[3...].joined(separator: "\t"))
        }
    }

    /// Окна `rick-*` без метки — пометить; чат без окна в hub — связать его первое окно; окно hub с меткой, которого нет
    /// ни в одной `rick-*`, — убить (окно без метки — вкладка человека, остаётся); заглушка уходит, когда в hub есть
    /// что-то ещё; убили бы все — заглушку оставить (нет — завести). `link: false` — чаты не связывать (iTerm спрятан).
    static func plan(_ windows: [Window], link: Bool = true) -> Plan {
        let rick = windows.filter { $0.session.hasPrefix("rick-") && $0.session.count > 5 }
        let rickIDs = Set(rick.map(\.id))
        let hub = windows.filter { $0.session == session }
        let hubIDs = Set(hub.map(\.id))
        var plan = Plan()
        var seen = Set<String>()
        for window in rick {
            if !window.chat, !plan.mark.contains(window.id) { plan.mark.append(window.id) }
            guard link, seen.insert(window.session).inserted else { continue }
            if !rick.contains(where: { $0.session == window.session && hubIDs.contains($0.id) }) {
                plan.link.append(window)
            }
        }
        let dead = hub.filter { $0.chat && !rickIDs.contains($0.id) }.map(\.id)
        let placeholders = hub.filter { !$0.chat && $0.name == placeholder }.map(\.id)
        if hub.count - dead.count - placeholders.count + plan.link.count > 0 {
            plan.kill = dead + placeholders
        } else {
            plan.kill = dead
            plan.placeholder = placeholders.isEmpty && !dead.isEmpty
        }
        return plan
    }

    /// Ответ `list-clients -F '#{client_control_mode}'`: подключён ли iTerm (`tmux -CC`).
    static func controlled(_ text: String) -> Bool {
        text.components(separatedBy: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == "1" }
    }

    // MARK: исполнение

    static func exists(tmux: String) -> Bool {
        FlowShell.run(tmux, ["has-session", "-t", "=" + session])?.status == 0
    }

    static func controlled(tmux: String) -> Bool {
        guard let out = FlowShell.run(tmux, ["list-clients", "-t", "=" + session, "-F", "#{client_control_mode}"]),
              out.status == 0 else { return false }
        return controlled(out.text)
    }

    /// Окно чата — в hub: метка чата (до связи — иначе умерший чат остался бы в hub навсегда), имя окна и панели —
    /// заголовок (вкладка iTerm), заголовки сессии как у `retitle`.
    static func link(tmux: String, session name: String, window: String, title: String) {
        _ = FlowShell.run(tmux, ["set-option", "-w", "-t", window, chatOption, "1"])
        retitle(tmux: tmux, session: name, window: window, title: title)
        _ = FlowShell.run(tmux, ["link-window", "-d", "-s", window, "-t", "=" + session + ":"])
    }

    /// Имя окна и панели — заголовок (вкладка iTerm), заголовки сессии как у `retitle`.
    static func retitle(tmux: String, session name: String, window: String, title: String) {
        PanelTerminals.retitleTmux(tmux, session: name, title: title)
        _ = FlowShell.run(tmux, ["rename-window", "-t", window, title])
        _ = FlowShell.run(tmux, ["select-pane", "-t", window, "-T", title])
    }

    /// Первое окно каждой `rick-*`, чьё имя не заголовок проекта, — с нужным заголовком.
    static func renames(_ windows: [Window], title: (String) -> String) -> [(Window, String)] {
        var seen = Set<String>()
        var out: [(Window, String)] = []
        for window in windows where window.session.hasPrefix("rick-") && window.session.count > 5 {
            guard seen.insert(window.session).inserted else { continue }
            let want = title(String(window.session.dropFirst(5)))
            if !want.isEmpty, window.name != want { out.append((window, want)) }
        }
        return out
    }

    /// Нажатие строки панели: окно чата — в hub, его вкладка — выбрана; iTerm подключён — вперёд, нет — открыть
    /// окно hub. Ответ — «shown», «opened» или nil.
    static func show(tmux: String, session name: String, title: String) -> String? {
        ITermQuiet.shared.allow()
        guard let own = FlowShell.run(tmux, ["list-windows", "-t", "=rick-\(name)", "-F", "#{window_id}"]),
              own.status == 0, let window = own.text.components(separatedBy: "\n").first, window.hasPrefix("@")
        else { return nil }
        let inHub = FlowShell.run(tmux, ["list-windows", "-t", "=" + session, "-F", "#{window_id}"])?.text ?? ""
        if !inHub.components(separatedBy: "\n").contains(window) {
            link(tmux: tmux, session: name, window: window, title: title)
        }
        _ = FlowShell.run(tmux, ["select-window", "-t", "=\(session):\(window)"])
        if controlled(tmux: tmux), let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
            return "shown"
        }
        return open(tmux: tmux) ? "opened" : nil
    }

    /// Окно iTerm с hub по нажатию человека: `open -a iTerm hub.command` (без AppleScript — права управлять iTerm у
    /// Пимпа нет). Предохранитель держит (`alarm`, #10976) — не открываем.
    @discardableResult
    static func open(tmux: String) -> Bool {
        ensureProfile()
        guard alarm() == nil, let file = ensureCommand(tmux: tmux) else { return false }
        return FlowShell.run("/usr/bin/open", ["-a", "iTerm", file.path], timeout: 10)?.status == 0
    }

    /// Скрытая настройка iTerm (3.7.6, «Open tmux windows and tabs in the background»): без неё iTerm на каждое новое
    /// окно tmux — Рик сменил чат, вкладка связалась в hub — переводит туда фокус, и окно выскакивает поверх работы
    /// (#11016). С ней вкладка появляется, фокус остаётся где был. Пишем, только когда ключа нет: выключил человек —
    /// его выбор.
    static let backgroundKey = "tmuxWindowsOpenInBackground"

    @discardableResult
    static func ensureBackgroundTabs(domain: String = bundle) -> Bool {
        guard CFPreferencesCopyAppValue(backgroundKey as CFString, domain as CFString) == nil else { return false }
        CFPreferencesSetAppValue(backgroundKey as CFString, kCFBooleanTrue, domain as CFString)
        return CFPreferencesAppSynchronize(domain as CFString)
    }

    /// `hub.command` — пишет сам Пимп: нет файла или он другой — записать (атомарно, права 0700: только хозяину, но
    /// исполняемый — iTerm его запускает).
    @discardableResult
    static func ensureCommand(tmux: String, file: URL = commandFile) -> URL? {
        let body = command(tmux: tmux)
        if (try? String(contentsOf: file, encoding: .utf8)) != body {
            guard SupportFiles.writeAtomic(file, Data(body.utf8), permissions: 0o700) else { return nil }
        } else if !FileManager.default.isExecutableFile(atPath: file.path) {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        }
        return file
    }

    /// Скрипт запуска окна iTerm: недостающие окна чатов — в hub, затем `tmux -CC attach` (второе окно не открывает).
    static func command(tmux: String) -> String {
        """
        #!/bin/sh
        # Сводное окно iTerm2 (#10564), файл пишет Пимп: все терминальные чаты rick-* — вкладками одного окна (tmux -CC), вкладки слева,
        # в названии — только имя проекта. Окна чатов не копируются, а связываются (link-window): чат один, клиентов два.
        TM=\(tmux)
        HUB=pimp-hub
        # Уже подключено окно iTerm к сводной сессии — второе не открываем.
        if $TM list-clients -t "=$HUB" -F '#{client_control_mode}' 2>/dev/null | grep -q 1; then exit 0; fi
        $TM has-session -t "=$HUB" 2>/dev/null || $TM new-session -d -s "$HUB" -n pimp-hub-start
        for line in $($TM list-sessions -F '#{session_name}' | grep '^rick-'); do
          window=$($TM list-windows -t "=$line" -F '#{window_id}' | head -1)
          [ -n "$window" ] || continue
          # Метка окна чата: умрёт чат — Пимп уберёт его вкладку; вкладки без метки (открытые человеком) не трогает.
          $TM set-option -w -t "$window" @pimp-chat 1
          name=$($TM show-options -v -t "=$line:" set-titles-string 2>/dev/null)
          [ -n "$name" ] && $TM rename-window -t "$window" "$name"
          $TM list-windows -t "=$HUB" -F '#{window_id}' | grep -qx "$window" || $TM link-window -d -s "$window" -t "=$HUB:"
        done
        # Заглушку — только когда в сводной есть что-то ещё: с последним окном умерла бы сама сессия.
        if [ $($TM list-windows -t "=$HUB" -F x | wc -l) -gt 1 ]; then
          $TM kill-window -t "=$HUB:pimp-hub-start" 2>/dev/null
        fi
        # Раскладку окон iTerm держит в самой сессии (@affinities): по старой вкладки разъехались бы по своим окнам, без неё
        # все — вкладками одного окна (#10976).
        $TM set-option -u -t "=$HUB:" @affinities 2>/dev/null
        exec $TM -CC attach -t "=$HUB"

        """
    }
}
