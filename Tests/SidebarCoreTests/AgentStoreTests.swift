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
    #expect(await eventually { store.color == .yellow })
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
