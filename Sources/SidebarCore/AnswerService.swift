import Foundation

public enum AnswerError: Error, Equatable, CustomStringConvertible {
    case promptChanged
    case chooseOption
    case useTerminal
    case agentBusy

    public var description: String {
        switch self {
        case .promptChanged: "Prompt changed"
        case .chooseOption: "Choose an option above"
        case .useTerminal: "Answer this prompt in the terminal"
        case .agentBusy: "Agent is busy"
        }
    }
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

    /// In an option menu, Enter picks the highlighted option. So text goes only into a
    /// "Type something" option, and never into a menu without one.
    public func reply(text: String, paneID: String, options: [PromptOption], isMenu: Bool = false) async throws {
        if options.isEmpty && isMenu { throw AnswerError.useTerminal }
        let freeText = options.first { $0.label.lowercased().hasPrefix("type something") }
        if !options.isEmpty && freeText == nil { throw AnswerError.chooseOption }
        try await ensureBlocked(paneID)
        if let freeText { try await api.sendKeys(paneID, [String(freeText.number)]) }
        try await api.sendText(paneID, text)
        try await api.sendKeys(paneID, ["enter"])
    }

    /// Gives a finished or idle agent its next task. Refused while it waits or works,
    /// so the text never lands in a question menu or interrupts a running job.
    public func nextTask(text: String, paneID: String) async throws {
        let status = try await api.getAgent(paneID).status
        guard status == .done || status == .idle else { throw AnswerError.agentBusy }
        try await api.prompt(paneID, text)
    }

    private func ensureBlocked(_ paneID: String) async throws {
        guard try await api.getAgent(paneID).status == .blocked else {
            throw AnswerError.promptChanged
        }
    }
}
