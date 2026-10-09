import Foundation

public protocol HerdrAPI: Sendable {
    func listAgents() async throws -> [Agent]
    func getAgent(_ paneID: String) async throws -> Agent
    func read(_ paneID: String, lines: Int) async throws -> String
    func sendKeys(_ paneID: String, _ keys: [String]) async throws
    func prompt(_ paneID: String, _ text: String) async throws
    func focus(_ paneID: String) async throws
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

    public func prompt(_ paneID: String, _ text: String) async throws {
        _ = try await call("agent.prompt", ["target": paneID, "text": text])
    }

    public func focus(_ paneID: String) async throws {
        _ = try await call("agent.focus", ["target": paneID])
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
