import Testing
@testable import SidebarCore

@Test func choiceSendsOptionKeyWhenBlocked() async throws {
    let api = FakeAPI()
    api.agents = [agent("w1:p1", .blocked)]
    try await AnswerService(api: api).choose(option: 2, paneID: "w1:p1")
    #expect(api.sentKeys == [Call(pane: "w1:p1", value: "2")])
}

@Test func choiceRefusedWhenAgentNoLongerBlocked() async {
    let api = FakeAPI()
    api.agents = [agent("w1:p1", .working)]
    await #expect(throws: AnswerError.promptChanged) {
        try await AnswerService(api: api).choose(option: 1, paneID: "w1:p1")
    }
    #expect(api.sentKeys.isEmpty)
}

@Test func replyRefusedWhenAgentNoLongerBlocked() async {
    let api = FakeAPI()
    api.agents = [agent("w1:p1", .done)]
    await #expect(throws: AnswerError.promptChanged) {
        try await AnswerService(api: api).reply(text: "yes", paneID: "w1:p1")
    }
    #expect(api.prompts.isEmpty)
}

@MainActor @Test func promptChangedShowsMessageAndReloads() async {
    let api = FakeAPI()
    api.agents = [agent("w1:p1", .working)]
    api.screenText = "new screen"
    let model = PanelModel(store: AgentStore(api: api), api: api)
    await model.choose(1, for: "w1:p1")
    #expect(model.errors["w1:p1"] == "Prompt changed")
    #expect(model.screens["w1:p1"] == "new screen")
}

@MainActor @Test func blankReplySendsNothing() async {
    let api = FakeAPI()
    api.agents = [agent("w1:p1", .blocked)]
    let model = PanelModel(store: AgentStore(api: api), api: api)
    model.drafts["w1:p1"] = "   "
    await model.reply(for: "w1:p1")
    #expect(api.prompts.isEmpty)
}

@MainActor @Test func successfulReplySendsTrimmedTextAndClearsDraft() async {
    let api = FakeAPI()
    api.agents = [agent("w1:p1", .blocked)]
    let model = PanelModel(store: AgentStore(api: api), api: api)
    model.drafts["w1:p1"] = " use main \n"
    await model.reply(for: "w1:p1")
    #expect(api.prompts == [Call(pane: "w1:p1", value: "use main")])
    #expect(model.drafts["w1:p1"] == nil)
}

@MainActor @Test func sendFailureShowsHerdrMessage() async {
    let api = FakeAPI()
    api.agents = [agent("w1:p1", .blocked)]
    api.sendError = HerdrError.server(code: "pane_gone", message: "pane w1:p1 is gone")
    let model = PanelModel(store: AgentStore(api: api), api: api)
    await model.choose(1, for: "w1:p1")
    #expect(model.errors["w1:p1"] == "pane w1:p1 is gone")
    #expect(model.sending.isEmpty)
}

@MainActor @Test func optionsComeFromLoadedScreen() async {
    let api = FakeAPI()
    api.screenText = "Do you want to proceed?\n❯ 1. Yes\n  2. No"
    let model = PanelModel(store: AgentStore(api: api), api: api)
    await model.reload("w1:p1")
    #expect(model.options(for: "w1:p1").map(\.label) == ["Yes", "No"])
}
