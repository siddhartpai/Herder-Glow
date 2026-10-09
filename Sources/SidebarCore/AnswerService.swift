import Foundation

public enum AnswerError: Error, Equatable, CustomStringConvertible {
    case promptChanged

    public var description: String { "Prompt changed" }
}

/// Sends answers only to agents that herdr reports as `blocked` at send time.
public struct AnswerService: Sendable {
    private let api: any HerdrAPI

    public init(api: any HerdrAPI) {
        self.api = api
    }

    public func choose(option: Int, paneID: String) async throws {
        try await ensureBlocked(paneID)
        try await api.sendKeys(paneID, [String(option)])
    }

    public func reply(text: String, paneID: String) async throws {
        try await ensureBlocked(paneID)
        try await api.prompt(paneID, text)
    }

    private func ensureBlocked(_ paneID: String) async throws {
        guard try await api.getAgent(paneID).status == .blocked else {
            throw AnswerError.promptChanged
        }
    }
}
