import Foundation
import Observation

@MainActor @Observable
public final class AgentStore {
    public private(set) var agents: [Agent] = []
    public private(set) var connected = false

    public var color: LightColor { LightColor.compute(connected: connected, agents: agents) }
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

    public func apply(_ event: HerdrEvent) {
        switch event {
        case let .statusChanged(paneID, status):
            if let index = agents.firstIndex(where: { $0.paneID == paneID }) {
                agents[index].status = status
                agents[index].activity = (agents.map(\.activity).max() ?? 0) + 1
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
