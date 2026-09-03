import Foundation

/// Канал команд в страницы Claude: `~/Library/Application Support/MyClaude/command.json`.
/// Лоадер v6 (patch-claude.mjs) читает файл по `fs.watchFile` раз в 500 мс, отбрасывает
/// команду с тем же `id`, и рассылает `{id, action, at, …}` событием `myclaude-command`
/// во все страницы (inject.js:1401–1425). Канал probe.js (лоадер v5) сюда не переносится.
final class CommandChannel {
    /// Папку не переименовывать: лоадер смотрит именно в MyClaude.
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/MyClaude", isDirectory: true)
    static let path = directory.appendingPathComponent("command.json")

    private(set) var lastCommand = "(none)"

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f
    }()

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// Экранирование как в Lua `jsonString`: кавычка, слэш и любые управляющие — \u00xx.
    static func jsonString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    /// Уникальный id: миллисекунды + случайные четыре цифры (формат Lua «%d-%04d»).
    /// Уникальность важна — лоадер игнорирует команду с прежним id.
    static func makeID(now: TimeInterval = Date().timeIntervalSince1970,
                       random: Int = Int.random(in: 0...9999)) -> String {
        String(format: "%d-%04d", Int(now * 1000), random)
    }

    /// Тело command.json. Порядок полей — как в Lua: id, action, at, затем дополнительные.
    static func payload(action: String, extra: [String: String] = [:],
                        id: String = makeID(), at: Date = Date()) -> String {
        var fields = ["\"id\":\(jsonString(id))",
                      "\"action\":\(jsonString(action))",
                      "\"at\":\(jsonString(stamp.string(from: at)))"]
        for key in extra.keys.sorted() {
            fields.append("\(jsonString(key)):\(jsonString(extra[key] ?? ""))")
        }
        return "{" + fields.joined(separator: ",") + "}"
    }

    /// Запись через временный файл рядом и `rename(2)`: лоадер опрашивает файл и не должен
    /// увидеть его наполовину записанным. tmp обязан лежать в той же папке — иначе rename не атомарен.
    @discardableResult
    static func writeAtomic(_ url: URL, _ body: String) -> Bool {
        let tmp = url.appendingPathExtension("tmp")
        let data = Data(body.utf8)
        do {
            try data.write(to: tmp, options: .atomic)
        } catch {
            // Патч ещё не ставили: папки MyClaude нет.
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            guard (try? data.write(to: tmp, options: .atomic)) != nil else { return false }
        }
        let moved = tmp.withUnsafeFileSystemRepresentation { from -> Bool in
            url.withUnsafeFileSystemRepresentation { to -> Bool in
                guard let from = from, let to = to else { return false }
                return rename(from, to) == 0
            }
        }
        if !moved { try? FileManager.default.removeItem(at: tmp) }
        return moved
    }

    @discardableResult
    func write(action: String, extra: [String: String] = [:]) -> Bool {
        let body = CommandChannel.payload(action: action, extra: extra)
        guard CommandChannel.writeAtomic(CommandChannel.path, body) else { return false }
        lastCommand = "\(action) @ \(CommandChannel.clock.string(from: Date()))"
        return true
    }
}
