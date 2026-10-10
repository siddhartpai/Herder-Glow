import Testing
@testable import SidebarCore

@MainActor @Test func refreshLoadsAgentsAndSubscribesToTheirPanes() async {
    let api = FakeAPI()
    api.agents = [agent("w1:p1", .working), agent("w1:p2", .blocked)]
    let store = AgentStore(api: api)
    await store.refresh()
    #expect(store.connected)
    #expect(store.color == .red)
    #expect(api.subscribedPaneIDs == ["w1:p1", "w1:p2"])
    #expect(store.blocked.map(\.paneID) == ["w1:p2"])
    #expect(store.others.map(\.paneID) == ["w1:p1"])
}

@MainActor @Test func statusEventUpdatesOneAgent() async {
    let api = FakeAPI()
    api.agents = [agent("w1:p1", .working), agent("w1:p2", .blocked)]
    let store = AgentStore(api: api)
    await store.refresh()
    api.emit(.statusChanged(paneID: "w1:p2", status: .done))
    #expect(await eventually { store.color == .blue })
}

@MainActor @Test func topologyEventReloadsAndResubscribes() async {
    let api = FakeAPI()
    api.agents = [agent("w1:p1", .idle)]
    let store = AgentStore(api: api)
    await store.refresh()
    api.agents.append(agent("w2:p1", .blocked))
    api.emit(.topologyChanged)
    #expect(await eventually { api.subscribedPaneIDs == ["w1:p1", "w2:p1"] })
    #expect(store.color == .red)
    #expect(api.subscriptions.first?.cancelled == true)
}

@MainActor @Test func listFailureShowsGreyThenRecovers() async {
    let api = FakeAPI()
    api.listError = HerdrError.socket("cannot connect")
    let store = AgentStore(api: api, retryDelay: .milliseconds(50))
    await store.refresh()
    #expect(store.connected == false)
    #expect(store.color == .grey)
    api.listError = nil
    #expect(await eventually { store.connected })
}

@MainActor @Test func subscriptionCloseTriggersReconnect() async {
    let api = FakeAPI()
    api.agents = [agent("w1:p1", .working)]
    let store = AgentStore(api: api, retryDelay: .milliseconds(50))
    await store.refresh()
    api.close(HerdrError.socket("connection closed"))
    #expect(await eventually { api.listCalls == 2 && store.connected })
}

@Test func agentReadsActivityFromStateChangeSeq() {
    let agent = Agent(json: ["pane_id": "w1:p1", "agent_status": "idle", "state_change_seq": 830])
    #expect(agent?.activity == 830)
}

@MainActor @Test func mostRecentAgentsComeFirst() async {
    let api = FakeAPI()
    var old = agent("w1:p1", .idle); old.activity = 10
    var new = agent("w1:p2", .done); new.activity = 50
    var mid = agent("w1:p3", .working); mid.activity = 30
    api.agents = [old, new, mid]
    let store = AgentStore(api: api)
    await store.refresh()
    let model = PanelModel(store: store, api: api)
    #expect(model.rows.map(\.paneID) == ["w1:p2", "w1:p3", "w1:p1"])
}

@MainActor @Test func statusChangeMovesAgentToTop() async {
    let api = FakeAPI()
    var a = agent("w1:p1", .idle); a.activity = 10
    var b = agent("w1:p2", .idle); b.activity = 50
    api.agents = [a, b]
    let store = AgentStore(api: api)
    await store.refresh()
    store.apply(.statusChanged(paneID: "w1:p1", status: .working))
    let model = PanelModel(store: store, api: api)
    #expect(model.rows.map(\.paneID) == ["w1:p1", "w1:p2"])
}

@MainActor @Test func newestWaitingCardComesFirst() async {
    let api = FakeAPI()
    var a = agent("w1:p1", .blocked); a.activity = 10
    var b = agent("w1:p2", .blocked); b.activity = 50
    api.agents = [a, b]
    let store = AgentStore(api: api)
    await store.refresh()
    #expect(PanelModel(store: store, api: api).cards.map(\.paneID) == ["w1:p2", "w1:p1"])
}
