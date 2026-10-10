import Foundation

public enum AgentStatus: String, Sendable {
    case idle, working, blocked, done, unknown
}

public struct Agent: Identifiable, Equatable, Sendable {
    public var paneID: String
    public var title: String
    public var cwd: String
    public var status: AgentStatus
    /// Claude Code session id, used to find the transcript.
    public var sessionID: String?
    /// Higher means the agent's state changed more recently (herdr `state_change_seq`).
    public var activity: Int = 0
    public var id: String { paneID }

    public init(paneID: String, title: String, cwd: String, status: AgentStatus, sessionID: String? = nil) {
        self.paneID = paneID
        self.title = title
        self.cwd = cwd
        self.status = status
        self.sessionID = sessionID
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
        let session = json["agent_session"] as? [String: Any]
        self.sessionID = session?["kind"] as? String == "id" ? session?["value"] as? String : nil
        self.activity = json["state_change_seq"] as? Int ?? 0
    }
}

public enum LightColor: Equatable, Sendable {
    case grey, red, blue, green

    public static func compute(connected: Bool, agents: [Agent]) -> LightColor {
        guard connected else { return .grey }
        if agents.contains(where: { $0.status == .blocked }) { return .red }
        if agents.contains(where: { $0.status == .working }) { return .blue }
        return .green
    }
}
