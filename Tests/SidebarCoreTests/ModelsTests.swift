import Testing
@testable import SidebarCore

private func agents(_ statuses: AgentStatus...) -> [Agent] {
    statuses.enumerated().map { Agent(paneID: "p\($0.offset)", title: "", cwd: "", status: $0.element) }
}

@Test func agentParsesFromAgentInfoJSON() {
    let agent = Agent(json: ["pane_id": "w1:p1", "agent_status": "blocked",
                             "terminal_title_stripped": "Fix bug", "cwd": "/tmp/a", "agent": "claude"])
    #expect(agent == Agent(paneID: "w1:p1", title: "Fix bug", cwd: "/tmp/a", status: .blocked))
}

@Test func agentFallsBackToAgentNameWhenTitleEmpty() {
    let agent = Agent(json: ["pane_id": "w1:p1", "agent_status": "idle",
                             "terminal_title_stripped": "", "agent": "claude"])
    #expect(agent?.title == "claude")
}

@Test func unknownStatusMapsToUnknown() {
    #expect(Agent(json: ["pane_id": "w1:p1", "agent_status": "sleeping"])?.status == .unknown)
}

@Test func agentWithoutPaneIDIsRejected() {
    #expect(Agent(json: ["agent_status": "idle"]) == nil)
}

@Test func greyWhenDisconnected() {
    #expect(LightColor.compute(connected: false, agents: agents(.blocked)) == .grey)
}

@Test func redWhenAnyBlocked() {
    #expect(LightColor.compute(connected: true, agents: agents(.working, .blocked, .done)) == .red)
}

@Test func blueWhenWorkingAndNoneBlocked() {
    #expect(LightColor.compute(connected: true, agents: agents(.working, .done)) == .blue)
}

@Test func greenWhenAllDoneIdleOrUnknown() {
    #expect(LightColor.compute(connected: true, agents: agents(.done, .idle, .unknown)) == .green)
}

@Test func greenWhenNoAgents() {
    #expect(LightColor.compute(connected: true, agents: []) == .green)
}
