import Foundation

/// Корень автодоверия страницы (WF108, контракт `trust-root` плана ред. 3): приложение шлёт всем страницам
/// `{"id","action":"trust-root","at","root":"/abs/path/"|null}`, страница кладёт `root` в
/// `localStorage["myclaude-trust-root-v1"]`; корня нет — автодоверие выключено. Корень — `projectsRoot`
/// из claude.json, ТОЛЬКО заданный явно: умолчание `StatusFeed` (`~/Projects`) доверия не даёт.
/// Здесь — чистая часть: конфиг → корень или nil, поля команды.
enum TrustRoot {
    static let action = "trust-root"

    /// `projectsRoot` из тела claude.json: `~` раскрыт от `home`, путь стандартизован, `/` на конце.
    /// Нет файла, ключа, не строка, пусто, относительный путь или сам `/` — nil.
    static func root(config data: Data?, home: String = NSHomeDirectory()) -> String? {
        guard let data = data,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let raw = (json[StatusFeed.configKey] as? String)?.trimmingCharacters(in: .whitespaces),
              !raw.isEmpty else { return nil }
        let expanded: String
        if raw == "~" || raw.hasPrefix("~/") {
            expanded = home + raw.dropFirst()
        } else {
            expanded = NSString(string: raw).expandingTildeInPath
        }
        guard expanded.hasPrefix("/") else { return nil }
        let path = URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL.path
        guard path != "/", path.hasPrefix("/") else { return nil }
        return path.hasSuffix("/") ? path : path + "/"
    }

    /// Корень из живого claude.json.
    static func current(configURL: URL = CommandChannel.directory
        .appendingPathComponent(StatusFeed.configFileName)) -> String? {
        root(config: try? Data(contentsOf: configURL))
    }

    /// Поля команды после id, action, at: `root` строкой или `null`.
    static func fields(root: String?) -> [(key: String, value: CommandValue)] {
        [(key: "root", value: root.map { .string($0) } ?? .null)]
    }
}
