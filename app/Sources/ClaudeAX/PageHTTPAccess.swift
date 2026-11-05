import Foundation

extension HtmlChromeOpener {
    enum PageAccess: Equatable {
        case reject(Int)
        case browser(preflight: Bool)
        case native

        var performsAction: Bool {
            self == .browser(preflight: false) || self == .native
        }
    }

    /// Заголовок запроса к порту: строка запроса (3 части) и поля (имена строчными); nil — битый (400).
    /// Общий для `checkPage` и `checkSummary` (#9806).
    static func parseHead(_ head: String) -> (parts: [Substring], headers: [String: [String]])? {
        guard head.utf8.count <= maxHead, let end = head.range(of: "\r\n\r\n") else { return nil }
        let lines = head[..<end.lowerBound].components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, ["HTTP/1.0", "HTTP/1.1"].contains(String(parts[2])),
              parts[1].hasPrefix("/"), !parts[1].hasPrefix("//"),
              !parts[1].unicodeScalars.contains(where: { $0.value < 33 || $0.value == 127 }) else { return nil }
        var headers: [String: [String]] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex else { return nil }
            let name = String(line[..<colon])
            guard name.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0)
                || (48...57).contains($0) || "!#$%&'*+-.^_`|~".utf8.contains($0) }) else { return nil }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !value.unicodeScalars.contains(where: { ($0.value < 32 && $0.value != 9) || $0.value == 127 })
            else { return nil }
            headers[name.lowercased(), default: []].append(value)
        }
        return (parts, headers)
    }

    /// Ровно один Host, и он — этот порт на loopback.
    static func loopbackHost(_ headers: [String: [String]]) -> Bool {
        guard let hosts = headers["host"], hosts.count == 1 else { return false }
        return ["127.0.0.1:\(port)", "localhost:\(port)"].contains(hosts[0].lowercased())
    }

    /// Browser Origin is mandatory, including inherited-origin about:blank popouts.
    /// Origin-less clients must authenticate separately; a token never overrides a foreign Origin.
    static func checkPage(_ head: String, token: String?) -> PageAccess {
        guard let (parts, headers) = parseHead(head) else { return .reject(400) }
        guard loopbackHost(headers) else { return .reject(403) }
        guard headers["transfer-encoding"] == nil,
              headers["content-length"] == nil || headers["content-length"] == ["0"] else { return .reject(400) }
        let browser: Bool
        if let origins = headers["origin"] {
            guard origins == ["https://claude.ai"] else { return .reject(403) }
            browser = true
        } else {
            guard let token = token, !token.isEmpty, let given = headers["x-pimp-viewer-token"],
                  given.count == 1, constantTimeEqual(given[0], token) else { return .reject(403) }
            browser = false
        }
        guard parts[0] == "GET" || parts[0] == "OPTIONS" else { return .reject(405) }
        guard let target = URLComponents(string: "http://127.0.0.1" + parts[1]),
              ["/open-html", "/viewer", "/copy-file", "/context", "/composer-font", "/panel", "/digest", "/kickoff", "/thumb",
               "/one-chat", "/dock", "/media-thumb", "/media-file", "/dock-shot", "/open-link"].contains(target.path)
        else { return .reject(404) }
        if parts[0] == "OPTIONS" {
            guard browser, headers["access-control-request-method"] == ["GET"],
                  headers["access-control-request-headers"] == nil else { return .reject(403) }
            return .browser(preflight: true)
        }
        return browser ? .browser(preflight: false) : .native
    }

    static func pageResponse(_ access: PageAccess) -> Data {
        let status: Int
        if case .reject(let code) = access { status = code } else { status = 204 }
        return httpResponse(status: status, contentType: nil, body: nil, access: access)
    }

    /// `200` с JSON сводки (К6 `GET /digest`); CORS — как у остальных ручек страницы.
    static func digestResponse(_ body: Data, access: PageAccess) -> Data {
        httpResponse(status: 200, contentType: "application/json; charset=utf-8", body: body, access: access)
    }

    /// К-TH `GET /thumb`: `200 image/jpeg` с миниатюрой; не вышло (чужой чат, закрытый путь, не фото) — `404`.
    /// CORS — как у `/digest`: тело читает только страница Claude.
    static func thumbResponse(_ jpeg: Data?, access: PageAccess) -> Data {
        httpResponse(status: jpeg == nil ? 404 : 200, contentType: jpeg == nil ? nil : "image/jpeg",
                     body: jpeg ?? Data(), access: access)
    }

    /// К-KO `GET /kickoff` (WF214): `200 text/plain` с текстом кикоффа Workflow; текста нет — `404`. CORS — как у
    /// `/digest`: страница отличает «текста нет» от «адреса нет» (старое приложение).
    static func kickoffResponse(_ text: String?, access: PageAccess) -> Data {
        httpResponse(status: text == nil ? 404 : 200, contentType: text == nil ? nil : "text/plain; charset=utf-8",
                     body: Data((text ?? "").utf8), access: access)
    }

    /// Ответ ручки страницы: статус, тип тела, CORS для браузера (только `https://claude.ai`, без credentials),
    /// длина и `no-store`. `body == nil` — ответ без тела: у `204` нет и `Content-Length`, у прочих он `0`.
    static func httpResponse(status: Int, contentType: String?, body: Data?, access: PageAccess) -> Data {
        let reason = [200: "OK", 204: "No Content", 400: "Bad Request", 403: "Forbidden", 404: "Not Found",
                      405: "Method Not Allowed", 503: "Service Unavailable"][status] ?? "Error"
        var response = "HTTP/1.1 \(status) \(reason)\r\n"
        if let contentType = contentType { response += "Content-Type: \(contentType)\r\n" }
        if case .browser = access {
            response += "Access-Control-Allow-Origin: https://claude.ai\r\nVary: Origin\r\n"
            response += "Access-Control-Allow-Methods: GET\r\nAccess-Control-Allow-Private-Network: true\r\n"
        }
        if let body = body {
            response += "Content-Length: \(body.count)\r\n"
        } else if status != 204 {
            response += "Content-Length: 0\r\n"
        }
        response += "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        return Data(response.utf8) + (body ?? Data())
    }
}
