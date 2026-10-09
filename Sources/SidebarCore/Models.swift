import Foundation

public enum AgentStatus: String, Sendable {
    case idle, working, blocked, done, unknown
}

public struct Agent: Identifiable, Equatable, Sendable {
    public var paneID: String
    public var title: String
    public var cwd: String
    public var status: AgentStatus
    public var id: String { paneID }

    public init(paneID: String, title: String, cwd: String, status: AgentStatus) {
        self.paneID = paneID
        self.title = title
        self.cwd = cwd
        self.status = status
    }

    /// Builds an agent from a herdr `AgentInfo` object.
    init?(json: [String: Any]) {
        guard let paneID = json["pane_id"] as? String,
              let status = json["agent_status"] as? String else { return nil }
        let title = json["terminal_title_stripped"] as? String
        self.paneID = paneID
        self.title = (title?.isEmpty == false ? title : nil) ?? (json["agent"] as? String) ?? paneID
        self.cwd = json["cwd"] as? String ?? ""
        self.status = AgentStatus(rawValue: status) ?? .unknown
    }
}

public enum LightColor: Equatable, Sendable {
    case grey, red, yellow, green

    public static func compute(connected: Bool, agents: [Agent]) -> LightColor {
        guard connected else { return .grey }
        if agents.contains(where: { $0.status == .blocked }) { return .red }
        if agents.contains(where: { $0.status == .working }) { return .yellow }
        return .green
    }
}
