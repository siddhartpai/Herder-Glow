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
    /// Option number being sent for each pane, so its button can show a spinner.
    public private(set) var pendingOption: [String: Int] = [:]
    /// The waiting card under the mouse; digit keys go to it.
    public var hoveredCard: String?
    public var drafts: [String: String] = [:]
    /// The agent row that shows its summary.
    public private(set) var expanded: String?
    public private(set) var summaries: [String: TranscriptSummary] = [:]
    /// Transcript titles, used as agent names.
    public private(set) var titles: [String: String] = [:]
    /// Shows the full panel even when only finished summaries would show.
    public var showAll = false
    /// Finished agents whose summaries this hover showed; seen when the panel closes.
    private var shownFinished: [String] = []

    public enum Mode: Equatable, Sendable {
        /// Only finished agents' summaries.
        case finished
        /// Waiting cards and all agent rows.
        case all
    }

    /// Panes given a next task in the last moment, so the view can show "Sent".
    public private(set) var sentNext: Set<String> = []

    public var mode: Mode {
        cards.isEmpty && !finishedAgents.isEmpty && !showAll ? .finished : .all
    }

    /// Finished agents shown in this hover, else those not seen yet; newest first.
    /// Cards shown in a hover stay until it closes, even after the agent starts its next task.
    public var finishedAgents: [Agent] {
        let panes = shownFinished.isEmpty ? store.finished.map(\.paneID) : shownFinished
        return newestFirst.filter { panes.contains($0.paneID) }
    }

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
        newestFirst.filter { $0.status == .blocked || answered.contains($0.paneID) }
    }

    public var rows: [Agent] {
        newestFirst.filter { $0.status != .blocked && !answered.contains($0.paneID) }
    }

    private var newestFirst: [Agent] {
        store.agents.enumerated()
            .sorted { ($0.element.activity, -$0.offset) > ($1.element.activity, -$1.offset) }
            .map(\.element)
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
        pendingOption[paneID] = option
        defer { pendingOption[paneID] = nil }
        await send(paneID) { try await $0.choose(option: option, paneID: paneID) }
    }

    /// The pane a digit key answers: the hovered card, else the first waiting card.
    /// Nil when that card has no such option or is already being answered.
    public func shortcutTarget(for digit: Int) -> String? {
        let ready = cards.filter { !answered.contains($0.paneID) && !sending.contains($0.paneID) }
        guard let pane = ready.first(where: { $0.paneID == hoveredCard })?.paneID ?? ready.first?.paneID,
              options(for: pane).contains(where: { $0.number == digit }) else { return nil }
        return pane
    }

    public func reply(for paneID: String) async {
        let text = drafts[paneID, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let options = options(for: paneID)
        let isMenu = PromptParser.isMenu(screens[paneID] ?? "")
        await send(paneID) { try await $0.reply(text: text, paneID: paneID, options: options, isMenu: isMenu) }
        if errors[paneID] == nil { drafts[paneID] = nil }
    }

    /// Opens one row's summary, or closes it if it is open.
    public func toggleSummary(_ paneID: String) async {
        guard expanded != paneID else {
            expanded = nil
            return
        }
        expanded = paneID
        await loadSummary(for: paneID)
    }

    /// Reloads the summary of the open row; the agent may have done more since it was loaded.
    public func refreshSummary(_ paneID: String) async {
        guard expanded == paneID || (mode == .finished && shownFinished.contains(paneID)) else { return }
        await loadSummary(for: paneID)
    }

    /// Called each time the panel opens.
    public func panelOpened() async {
        shownFinished = mode == .finished ? finishedAgents.map(\.paneID) : []
        await reloadBlocked()
        for paneID in shownFinished { await loadSummary(for: paneID) }
        if let expanded { await refreshSummary(expanded) }
    }

    /// Marks the finished summaries shown in this hover as seen, and resets the view.
    public func panelClosed() {
        store.markSeen(shownFinished)
        shownFinished = []
        showAll = false
    }

    /// The transcript title, else the terminal title.
    public func name(for agent: Agent) -> String {
        titles[agent.paneID] ?? agent.title
    }

    /// Reloads terminal titles and transcript titles, so names follow what each agent works on.
    public func refreshNames() async {
        await store.reloadNames()
        for agent in store.agents {
            guard let sessionID = agent.sessionID else {
                titles[agent.paneID] = nil
                continue
            }
            let summary = await Task.detached { [loadSummary] in await loadSummary(sessionID) }.value
            titles[agent.paneID] = summary?.title
        }
    }

    /// Reads the transcript summary; without a transcript, loads screen text.
    private func loadSummary(for paneID: String) async {
        let sessionID = store.agents.first { $0.paneID == paneID }?.sessionID
        if let sessionID, let summary = await Task.detached(operation: { [loadSummary] in
            await loadSummary(sessionID)
        }).value {
            summaries[paneID] = summary
        } else {
            await reload(paneID)
        }
    }

    /// Sends the draft as the agent's next task.
    public func sendNext(for paneID: String) async {
        let text = drafts[paneID, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        errors[paneID] = nil
        sending.insert(paneID)
        defer { sending.remove(paneID) }
        do {
            try await answers.nextTask(text: text, paneID: paneID)
            drafts[paneID] = nil
            sentNext.insert(paneID)
            Task { [weak self, answeredDuration] in
                try? await Task.sleep(for: answeredDuration)
                self?.sentNext.remove(paneID)
            }
        } catch {
            errors[paneID] = String(describing: error)
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
