import Foundation

public protocol HerdrSubscription: AnyObject, Sendable {
    func cancel()
}

public protocol HerdrAPI: Sendable {
    func listAgents() async throws -> [Agent]
    func getAgent(_ paneID: String) async throws -> Agent
    func read(_ paneID: String, lines: Int) async throws -> String
    func sendKeys(_ paneID: String, _ keys: [String]) async throws
    func sendText(_ paneID: String, _ text: String) async throws
    func focus(_ paneID: String) async throws
    func subscribe(paneIDs: [String],
                   onEvent: @escaping @Sendable (HerdrEvent) -> Void,
                   onClose: @escaping @Sendable (Error) -> Void) -> HerdrSubscription
}

/// Talks to the herdr server over its Unix socket. One connection per request.
public final class HerdrClient: HerdrAPI {
    public let socketPath: String

    public init(socketPath: String = HerdrClient.defaultSocketPath) {
        self.socketPath = socketPath
    }

    public static var defaultSocketPath: String {
        ProcessInfo.processInfo.environment["HERDR_SOCKET_PATH"]
            ?? NSHomeDirectory() + "/.config/herdr/herdr.sock"
    }

    public func listAgents() async throws -> [Agent] {
        let result = try await call("agent.list", [:])
        let list = result["agents"] as? [[String: Any]] ?? []
        return list.compactMap(Agent.init(json:))
    }

    public func getAgent(_ paneID: String) async throws -> Agent {
        let result = try await call("agent.get", ["target": paneID])
        guard let json = result["agent"] as? [String: Any], let agent = Agent(json: json) else {
            throw HerdrError.badResponse
        }
        return agent
    }

    public func read(_ paneID: String, lines: Int) async throws -> String {
        let result = try await call("agent.read", ["target": paneID, "source": "recent", "lines": lines])
        guard let read = result["read"] as? [String: Any], let text = read["text"] as? String else {
            throw HerdrError.badResponse
        }
        return text
    }

    public func sendKeys(_ paneID: String, _ keys: [String]) async throws {
        _ = try await call("agent.send_keys", ["target": paneID, "keys": keys])
    }

    /// Types literal text into the pane. herdr refuses `agent.prompt` while an agent is blocked.
    public func sendText(_ paneID: String, _ text: String) async throws {
        _ = try await call("pane.send_text", ["pane_id": paneID, "text": text])
    }

    public func focus(_ paneID: String) async throws {
        _ = try await call("agent.focus", ["target": paneID])
    }

    /// Opens a long-lived connection for events. `onClose` is not called after `cancel()`.
    public func subscribe(paneIDs: [String],
                          onEvent: @escaping @Sendable (HerdrEvent) -> Void,
                          onClose: @escaping @Sendable (Error) -> Void) -> HerdrSubscription {
        let subscription = SocketSubscription()
        let path = socketPath
        let subscriptions = HerdrEvent.topologyEvents.map { ["type": $0] }
            + paneIDs.map { ["type": "pane.agent_status_changed", "pane_id": $0] }
        let request: [String: Any] = ["id": "sub", "method": "events.subscribe",
                                      "params": ["subscriptions": subscriptions]]
        Thread {
            do {
                let socket = try LineSocket(path: path)
                defer { subscription.detach(); socket.close() }
                guard subscription.attach(socket) else { return }
                try socket.writeLine(JSONSerialization.data(withJSONObject: request))
                let started = try JSONSerialization.jsonObject(with: socket.readLine()) as? [String: Any] ?? [:]
                if let error = HerdrError(response: started) { throw error }
                while true {
                    let line = try socket.readLine()
                    if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                       let event = HerdrEvent.parse(object) {
                        onEvent(event)
                    }
                }
            } catch {
                if !subscription.isCancelled { onClose(error) }
            }
        }.start()
        return subscription
    }

    private func call(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        let path = socketPath
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try Self.callSync(path: path, method: method, params: params))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func callSync(path: String, method: String, params: [String: Any]) throws -> [String: Any] {
        let socket = try LineSocket(path: path)
        defer { socket.close() }
        let request: [String: Any] = ["id": UUID().uuidString, "method": method, "params": params]
        try socket.writeLine(JSONSerialization.data(withJSONObject: request))
        guard let response = try JSONSerialization.jsonObject(with: socket.readLine()) as? [String: Any] else {
            throw HerdrError.badResponse
        }
        if let error = HerdrError(response: response) { throw error }
        guard let result = response["result"] as? [String: Any] else { throw HerdrError.badResponse }
        return result
    }
}

final class SocketSubscription: HerdrSubscription, @unchecked Sendable {
    private let lock = NSLock()
    private var socket: LineSocket?
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let socket = self.socket
        lock.unlock()
        socket?.shutdown()
    }

    /// Returns false if `cancel()` already ran.
    func attach(_ socket: LineSocket) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { return false }
        self.socket = socket
        return true
    }

    func detach() {
        lock.lock(); socket = nil; lock.unlock()
    }
}
