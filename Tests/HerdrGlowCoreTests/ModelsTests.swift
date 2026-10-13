import Testing
@testable import HerdrGlowCore

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
    #expect(LightColor.compute(connected: true, agents: agents(.working, .idle)) == .blue)
}

@Test func greenWhenAnAgentFinishedAndIsUnseen() {
    #expect(LightColor.compute(connected: true, agents: agents(.done, .idle, .unknown)) == .green)
}

@Test func calmWhenFinishedAgentWasSeen() {
    var done = Agent(paneID: "p0", title: "", cwd: "", status: .done)
    done.completion = 7
    #expect(LightColor.compute(connected: true, agents: [done], seen: ["p0": 7]) == .calm)
}

@Test func finishedBeatsWorkingButNotWaiting() {
    #expect(LightColor.compute(connected: true, agents: agents(.working, .done)) == .green)
    #expect(LightColor.compute(connected: true, agents: agents(.done, .blocked)) == .red)
}

@Test func calmWhenAllIdle() {
    #expect(LightColor.compute(connected: true, agents: agents(.idle, .unknown)) == .calm)
}

@Test func calmWhenNoAgents() {
    #expect(LightColor.compute(connected: true, agents: []) == .calm)
}

@Test func agentReadsCompletionSeq() {
    #expect(Agent(json: ["pane_id": "w1:p1", "agent_status": "done", "completion_seq": 826])?.completion == 826)
}
