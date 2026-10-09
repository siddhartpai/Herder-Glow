import Foundation
import Observation

@MainActor @Observable
public final class PanelModel {
    public let store: AgentStore
    public private(set) var screens: [String: String] = [:]
    public private(set) var errors: [String: String] = [:]
    public private(set) var sending: Set<String> = []
    /// Panes answered in the last moment, so the view can show a check mark.
    public private(set) var answered: Set<String> = []
    public var drafts: [String: String] = [:]
    /// The agent row that shows its summary.
    public private(set) var expanded: String?
    public private(set) var summaries: [String: TranscriptSummary] = [:]

    private let api: any HerdrAPI
    private let answers: AnswerService
    private let answeredDuration: Duration
    private let loadSummary: @Sendable (String) async -> TranscriptSummary?

    public init(store: AgentStore, api: any HerdrAPI, answeredDuration: Duration = .milliseconds(1500),
                loadSummary: @escaping @Sendable (String) async -> TranscriptSummary? = { TranscriptSummary.load(sessionID: $0) }) {
        self.store = store
        self.api = api
        self.answers = AnswerService(api: api)
        self.answeredDuration = answeredDuration
        self.loadSummary = loadSummary
    }

    /// Blocked agents, plus agents just answered so their card can show the check mark.
    public var cards: [Agent] {
        store.agents.filter { $0.status == .blocked || answered.contains($0.paneID) }
    }

    public var rows: [Agent] {
        store.agents.filter { $0.status != .blocked && !answered.contains($0.paneID) }
    }

    public func options(for paneID: String) -> [PromptOption] {
        PromptParser.options(in: screens[paneID] ?? "")
    }

    public func reload(_ paneID: String) async {
        do {
            screens[paneID] = try await api.read(paneID, lines: 20)
        } catch {
            errors[paneID] = String(describing: error)
        }
    }

    public func reloadBlocked() async {
        for agent in store.blocked { await reload(agent.paneID) }
    }

    public func choose(_ option: Int, for paneID: String) async {
        await send(paneID) { try await $0.choose(option: option, paneID: paneID) }
    }

    public func reply(for paneID: String) async {
        let text = drafts[paneID, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let options = options(for: paneID)
        let isMenu = PromptParser.isMenu(screens[paneID] ?? "")
        await send(paneID) { try await $0.reply(text: text, paneID: paneID, options: options, isMenu: isMenu) }
        if errors[paneID] == nil { drafts[paneID] = nil }
    }

    /// Opens one row's summary, or closes it if it is open. Without a transcript, loads screen text.
    public func toggleSummary(_ paneID: String) async {
        guard expanded != paneID else {
            expanded = nil
            return
        }
        expanded = paneID
        let sessionID = store.agents.first { $0.paneID == paneID }?.sessionID
        if let sessionID, let summary = await Task.detached(operation: { [loadSummary] in
            await loadSummary(sessionID)
        }).value {
            summaries[paneID] = summary
        } else {
            await reload(paneID)
        }
    }

    public func focus(_ paneID: String) async {
        try? await api.focus(paneID)
    }

    private func send(_ paneID: String, _ operation: (AnswerService) async throws -> Void) async {
        errors[paneID] = nil
        sending.insert(paneID)
        defer { sending.remove(paneID) }
        do {
            try await operation(answers)
            answered.insert(paneID)
            Task { [weak self, answeredDuration] in
                try? await Task.sleep(for: answeredDuration)
                self?.answered.remove(paneID)
            }
        } catch AnswerError.promptChanged {
            errors[paneID] = String(describing: AnswerError.promptChanged)
            await reload(paneID)
        } catch {
            errors[paneID] = String(describing: error)
        }
    }
}
