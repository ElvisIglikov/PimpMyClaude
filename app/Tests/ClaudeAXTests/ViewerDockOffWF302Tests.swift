import Network
import XCTest
@testable import ClaudeAX

/// ✕ в PimpViewer → `/viewer-dock-off` (WF302, #11224; контракт К-V8 — `docs/contracts/080-wf97-wf104-pimp-viewer.md`):
/// те же проверки, что у `/viewer-nudge`; ответ `204` + `X-Pimp-Viewer: 1` всегда (дока нет — тоже 204), Пимп пишет
/// странице `dock {on:false, only:"owner"}`. Живой порт 47615 и `command.json` Элвиса не трогаем.
final class ViewerDockOffWF302Tests: XCTestCase {
    private let token = String(repeating: "c3", count: 16)

    private func head(_ target: String, method: String = "GET", host: [String] = ["127.0.0.1:47615"],
                      token: [String]? = nil) -> String {
        var lines = ["\(method) \(target) HTTP/1.1"]
        lines += host.map { "Host: \($0)" }
        lines += (token ?? [self.token]).map { "X-Pimp-Viewer-Token: \($0)" }
        return lines.joined(separator: "\r\n") + "\r\n\r\n"
    }

    private func check(_ head: String) -> HtmlChromeOpener.ChannelVerdict {
        HtmlChromeOpener.checkChannel(head, token: token)
    }

    func testRouteAndChecksAsNudge() {
        XCTAssertTrue(HtmlChromeOpener.isChannel(head("/viewer-dock-off")))
        XCTAssertEqual(check(head("/viewer-dock-off")), .dockOff)
        XCTAssertEqual(check(head("/viewer-dock-off?why=x", host: ["localhost:47615"])), .dockOff)
        XCTAssertEqual(check(head("/viewer-dock-off", host: ["evil.example:47615"])), .reject(403))
        XCTAssertEqual(check(head("/viewer-dock-off", host: [])), .reject(403))
        XCTAssertEqual(check(head("/viewer-dock-off", token: [])), .reject(403))
        XCTAssertEqual(check(head("/viewer-dock-off", token: [String(repeating: "d4", count: 16)])), .reject(403))
        XCTAssertEqual(HtmlChromeOpener.checkChannel(head("/viewer-dock-off"), token: nil), .reject(403))
        XCTAssertEqual(check(head("/viewer-dock-off", method: "OPTIONS")), .reject(403))
        XCTAssertEqual(check(head("/viewer-dock-off", method: "POST")), .reject(405))
        XCTAssertEqual(check(head("/viewer-dock-offx")), .reject(404))
    }

    func testCommandForPage() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dock-off-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("command.json")
        XCTAssertTrue(ClaudeAXController.writeDockOff(CommandChannel(path: file, now: Date.init, schedule: { _, _ in })))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(json["action"] as? String, "dock")
        XCTAssertEqual(json["on"] as? Bool, false)
        XCTAssertEqual(json["only"] as? String, "owner")
        XCTAssertEqual(json["scope"] as? String, "all")
    }

    // MARK: - по настоящему сокету

    private final class Server {
        let opener = HtmlChromeOpener()
        let listener: NWListener
        init(token: String) throws {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            listener = try NWListener(using: parameters)
            opener.channelToken = { token }
            listener.newConnectionHandler = { [opener] in opener.serve($0) }
            let ready = DispatchSemaphore(value: 0)
            listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
            listener.start(queue: DispatchQueue(label: "test.dock-off-server"))
            _ = ready.wait(timeout: .now() + 3)
        }
        deinit { listener.cancel() }

        func exchange(_ head: String) throws -> String {
            let port = try XCTUnwrap(listener.port)
            let connection = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
            let ended = DispatchSemaphore(value: 0)
            let lock = NSLock()
            var data = Data()
            func receive() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { bytes, _, done, error in
                    lock.lock()
                    if let bytes = bytes { data.append(bytes) }
                    lock.unlock()
                    if done || error != nil { ended.signal() } else { receive() }
                }
            }
            connection.stateUpdateHandler = { state in
                guard case .ready = state else { return }
                connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
                receive()
            }
            connection.start(queue: DispatchQueue(label: "test.dock-off-client"))
            defer { connection.cancel() }
            XCTAssertEqual(ended.wait(timeout: .now() + 5), .success)
            lock.lock()
            defer { lock.unlock() }
            return String(decoding: data, as: UTF8.self)
        }
    }

    func testAnswers204AndCallsDockOff() throws {
        let server = try Server(token: token)
        let called = expectation(description: "onDockOff")
        server.opener.onDockOff = { called.fulfill() }
        let answer = try server.exchange(head("/viewer-dock-off"))
        XCTAssertTrue(answer.hasPrefix("HTTP/1.1 204 "), answer)
        XCTAssertTrue(answer.contains("X-Pimp-Viewer: 1\r\n"), answer)
        XCTAssertFalse(answer.contains("Access-Control-"), answer)
        wait(for: [called], timeout: 2)
        // Без токена — 403 и ничего не закрыто.
        server.opener.onDockOff = { XCTFail("без токена панель не закрывают") }
        let refused = try server.exchange(head("/viewer-dock-off", token: []))
        XCTAssertTrue(refused.hasPrefix("HTTP/1.1 403 "), refused)
        XCTAssertFalse(refused.contains("X-Pimp-Viewer"), refused)
        // Нет контроллера (дока нет) — тоже 204.
        server.opener.onDockOff = nil
        XCTAssertTrue(try server.exchange(head("/viewer-dock-off")).hasPrefix("HTTP/1.1 204 "))
    }
}
