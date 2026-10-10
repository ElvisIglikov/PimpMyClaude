import Foundation
import Network
import XCTest
@testable import ClaudeAX

/// Real receive/serve over an ephemeral loopback socket. No live listener, files, browser,
/// main run loop or Claude instance participates; only the context callback is installed.
final class PageHTTPTransportTests: XCTestCase {
    private let chat = "local_301ae90e-755b-49e8-8ee1-ae716fb5ff2f"

    private final class Server {
        let opener = HtmlChromeOpener()
        let listener: NWListener
        let queue = DispatchQueue(label: "pimp-test.http-listener")
        let action = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var calls: [String] = []
        var contexts: [String] { lock.lock(); defer { lock.unlock() }; return calls }

        init() throws {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            listener = try NWListener(using: parameters)
            opener.channelToken = { nil }
            opener.onContext = { [weak self] chat in
                guard let self = self else { return }
                self.lock.lock(); self.calls.append(chat); self.lock.unlock()
                self.action.signal()
            }
            listener.newConnectionHandler = { [opener] connection in opener.serve(connection) }
            let ready = DispatchSemaphore(value: 0)
            listener.stateUpdateHandler = { state in
                switch state { case .ready, .failed: ready.signal(); default: break }
            }
            listener.start(queue: queue)
            guard ready.wait(timeout: .now() + 3) == .success, listener.port != nil else {
                listener.cancel()
                throw HarnessError.listener
            }
        }
        deinit { listener.cancel() }
        func client() throws -> Client { try Client(port: XCTUnwrap(listener.port)) }
    }

    private enum HarnessError: Error { case listener, client, send, response }

    private final class Client {
        let connection: NWConnection
        let queue = DispatchQueue(label: "pimp-test.http-client")
        let ended = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var data = Data()
        var response: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }

        init(port: NWEndpoint.Port) throws {
            connection = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
            let ready = DispatchSemaphore(value: 0)
            connection.stateUpdateHandler = { state in
                switch state { case .ready, .failed: ready.signal(); default: break }
            }
            connection.start(queue: queue)
            guard ready.wait(timeout: .now() + 3) == .success, case .ready = connection.state else {
                connection.cancel()
                throw HarnessError.client
            }
            receive()
        }
        deinit { connection.cancel() }
        private func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 32_768) { [weak self] bytes, _, done, error in
                guard let self = self else { return }
                self.lock.lock()
                if let bytes = bytes { self.data.append(bytes) }
                self.lock.unlock()
                if done || error != nil { self.ended.signal() } else { self.receive() }
            }
        }
        func send(_ text: String, final: Bool = false) throws {
            let sent = DispatchSemaphore(value: 0)
            let resultLock = NSLock()
            var failed = false
            connection.send(content: Data(text.utf8), contentContext: final ? .finalMessage : .defaultMessage,
                            isComplete: true, completion: .contentProcessed { error in
                resultLock.lock(); failed = error != nil; resultLock.unlock(); sent.signal()
            })
            guard sent.wait(timeout: .now() + 3) == .success else { throw HarnessError.send }
            resultLock.lock(); let didFail = failed; resultLock.unlock()
            if didFail { throw HarnessError.send }
        }
        func finish(timeout: TimeInterval = 3) throws -> String {
            guard ended.wait(timeout: .now() + timeout) == .success else { throw HarnessError.response }
            return response
        }
    }

    private func head(method: String = "GET", origin: String = "https://claude.ai", host: String = "127.0.0.1:47615") -> String {
        "\(method) /context?chat=\(chat) HTTP/1.1\r\nHost: \(host)\r\nOrigin: \(origin)\r\n"
    }

    func testSplitHeaderHasNoEffectUntilTerminatorAndAnswersWhileMainIsBlocked() throws {
        let body = {
            XCTAssertTrue(Thread.isMainThread)
            let server = try Server(), client = try server.client()
            try client.send(self.head())
            XCTAssertEqual(client.ended.wait(timeout: .now() + 0.2), .timedOut)
            XCTAssertTrue(client.response.isEmpty)
            XCTAssertTrue(server.contexts.isEmpty)
            try client.send("\r\n")
            // Synchronous semaphore waits deliberately block main: the real server must
            // finish on its own queue without DispatchQueue.main.sync or run-loop pumping.
            XCTAssertTrue(try client.finish().hasPrefix("HTTP/1.1 204"))
            XCTAssertEqual(server.action.wait(timeout: .now() + 1), .success)
            XCTAssertEqual(server.contexts, [self.chat])
        }
        if Thread.isMainThread { try body() } else { try DispatchQueue.main.sync(execute: body) }
    }

    func testHostileOriginsHostsAndPreflightNeverPerformAnAction() throws {
        let server = try Server()
        let requests: [(String, Int)] = [
            (head(origin: "https://evil.test") + "\r\n", 403),
            (head(origin: "null") + "\r\n", 403),
            (head(host: "evil.test:47615") + "\r\n", 403),
            (head(method: "OPTIONS") + "Access-Control-Request-Method: GET\r\n\r\n", 204)]
        for (request, status) in requests {
            let client = try server.client()
            try client.send(request)
            XCTAssertTrue(try client.finish().hasPrefix("HTTP/1.1 \(status)"))
        }
        XCTAssertTrue(server.contexts.isEmpty)
    }

    func testOversizedAndEarlyEOFAreRejectedWithoutEffects() throws {
        let server = try Server()
        let oversized = try server.client()
        try oversized.send(head() + "X-Padding: " + String(repeating: "x", count: HtmlChromeOpener.maxHead) + "\r\n\r\n")
        XCTAssertTrue(try oversized.finish().hasPrefix("HTTP/1.1 400"))
        let incomplete = try server.client()
        try incomplete.send(head(), final: true)
        XCTAssertTrue(try incomplete.finish().hasPrefix("HTTP/1.1 400"))
        XCTAssertTrue(server.contexts.isEmpty)
    }

    func testIncompleteHeaderUsesRealFiveSecondTimeoutAndCancelsWithoutEffects() throws {
        let server = try Server(), client = try server.client()
        let began = ProcessInfo.processInfo.systemUptime
        try client.send(head())
        XCTAssertTrue(try client.finish(timeout: HtmlChromeOpener.readTimeout + 3).isEmpty)
        let elapsed = ProcessInfo.processInfo.systemUptime - began
        XCTAssertGreaterThanOrEqual(elapsed, HtmlChromeOpener.readTimeout - 0.5)
        XCTAssertLessThan(elapsed, HtmlChromeOpener.readTimeout + 3)
        XCTAssertTrue(server.contexts.isEmpty)
    }
}
