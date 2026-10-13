import Foundation
import Observation

@MainActor @Observable
public final class AgentStore {
    public private(set) var agents: [Agent] = []
    public private(set) var connected = false

    /// Last completion number seen for each pane.
    public private(set) var seen: [String: Int] = [:]

    public var color: LightColor { LightColor.compute(connected: connected, agents: agents, seen: seen) }
    /// Agents that finished a job you have not seen yet.
    public var finished: [Agent] { agents.filter { $0.isUnseenFinish(seen) } }
    public var blocked: [Agent] { agents.filter { $0.status == .blocked } }
    public var others: [Agent] { agents.filter { $0.status != .blocked } }

    private let api: any HerdrAPI
    private let retryDelay: Duration
    private var subscription: HerdrSubscription?
    private var retryTask: Task<Void, Never>?

    public init(api: any HerdrAPI, retryDelay: Duration = .seconds(2)) {
        self.api = api
        self.retryDelay = retryDelay
    }

    public func start() {
        Task { await refresh() }
    }

    /// Reloads the agent list and re-subscribes to status events for its panes.
    public func refresh() async {
        do {
            agents = try await api.listAgents()
            connected = true
            subscription?.cancel()
            subscription = api.subscribe(
                paneIDs: agents.map(\.paneID),
                onEvent: { [weak self] event in Task { @MainActor in self?.apply(event) } },
                onClose: { [weak self] _ in Task { @MainActor in self?.disconnected() } })
        } catch {
            disconnected()
        }
    }

    /// Updates terminal titles and session ids. Status and the subscription stay as they are.
    public func reloadNames() async {
        guard let latest = try? await api.listAgents() else { return }
        for fresh in latest {
            guard let index = agents.firstIndex(where: { $0.paneID == fresh.paneID }) else { continue }
            agents[index].title = fresh.title
            agents[index].sessionID = fresh.sessionID
        }
    }

    public func markSeen(_ paneIDs: [String]) {
        for agent in agents where paneIDs.contains(agent.paneID) {
            seen[agent.paneID] = agent.completion
        }
    }

    public func apply(_ event: HerdrEvent) {
        switch event {
        case let .statusChanged(paneID, status):
            if let index = agents.firstIndex(where: { $0.paneID == paneID }) {
                agents[index].status = status
                agents[index].activity = (agents.map(\.activity).max() ?? 0) + 1
                if status == .done { agents[index].completion += 1 }
            }
        case .topologyChanged:
            Task { await refresh() }
        }
    }

    private func disconnected() {
        connected = false
        agents = []
        subscription?.cancel()
        subscription = nil
        guard retryTask == nil else { return }
        retryTask = Task { [weak self, retryDelay] in
            try? await Task.sleep(for: retryDelay)
            guard let self else { return }
            self.retryTask = nil
            await self.refresh()
        }
    }
}
