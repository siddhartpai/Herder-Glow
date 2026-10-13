import Foundation

public enum HerdrEvent: Equatable, Sendable {
    case statusChanged(paneID: String, status: AgentStatus)
    /// A pane or agent appeared or went away; the agent list must be reloaded.
    case topologyChanged

    static let topologyEvents = ["pane.created", "pane.closed", "pane.exited", "pane.agent_detected"]

    public static func parse(_ object: [String: Any]) -> HerdrEvent? {
        guard var name = object["event"] as? String else { return nil }
        // Live herdr sends lifecycle events as `pane_created`; subscriptions use `pane.created`.
        if name.hasPrefix("pane_") { name = "pane." + name.dropFirst("pane_".count) }
        let data = object["data"] as? [String: Any] ?? [:]
        if name == "pane.agent_status_changed" {
            guard let paneID = data["pane_id"] as? String,
                  let status = data["agent_status"] as? String else { return nil }
            return .statusChanged(paneID: paneID, status: AgentStatus(rawValue: status) ?? .unknown)
        }
        return topologyEvents.contains(name) ? .topologyChanged : nil
    }
}
