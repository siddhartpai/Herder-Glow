import Testing
@testable import HerderGlowCore

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
        try await AnswerService(api: api).reply(text: "yes", paneID: "w1:p1", options: [])
    }
    #expect(api.texts.isEmpty)
}

@Test func replyWithoutOptionsTypesTextThenEnter() async throws {
    let api = FakeAPI()
    api.agents = [agent("w1:p1", .blocked)]
    try await AnswerService(api: api).reply(text: "use main", paneID: "w1:p1", options: [])
    #expect(api.texts == [Call(pane: "w1:p1", value: "use main")])
    #expect(api.sentKeys == [Call(pane: "w1:p1", value: "enter")])
}

@Test func replyToMenuSelectsTypeSomethingFirst() async throws {
    let api = FakeAPI()
    api.agents = [agent("w1:p1", .blocked)]
    let options = [PromptOption(number: 1, label: "a.txt"), PromptOption(number: 2, label: "b.txt"),
                   PromptOption(number: 3, label: "Type something.")]
    try await AnswerService(api: api).reply(text: "c.txt", paneID: "w1:p1", options: options)
    #expect(api.sentKeys == [Call(pane: "w1:p1", value: "3"), Call(pane: "w1:p1", value: "enter")])
    #expect(api.texts == [Call(pane: "w1:p1", value: "c.txt")])
}

@Test func replyToMenuWithoutTypeSomethingSendsNothing() async {
    let api = FakeAPI()
    api.agents = [agent("w1:p1", .blocked)]
    let options = [PromptOption(number: 1, label: "Yes"), PromptOption(number: 2, label: "No")]
    await #expect(throws: AnswerError.chooseOption) {
        try await AnswerService(api: api).reply(text: "no thanks", paneID: "w1:p1", options: options)
    }
    #expect(api.sentKeys.isEmpty)
    #expect(api.texts.isEmpty)
}

@MainActor @Test func replyToUnnumberedMenuSendsNothing() async {
    let api = FakeAPI()
    api.agents = [agent("w1:p1", .blocked)]
    api.screenText = " ❯ No, exit\n   Yes, I trust this folder\n\n Enter to confirm · Esc to cancel"
    let model = PanelModel(store: AgentStore(api: api), api: api)
    await model.reload("w1:p1")
    model.drafts["w1:p1"] = "yes"
    await model.reply(for: "w1:p1")
    #expect(api.texts.isEmpty)
    #expect(api.sentKeys.isEmpty)
    #expect(model.errors["w1:p1"] == "Answer this prompt in the terminal")
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
    #expect(api.texts.isEmpty)
}

@MainActor @Test func successfulReplySendsTrimmedTextAndClearsDraft() async {
    let api = FakeAPI()
    api.agents = [agent("w1:p1", .blocked)]
    let model = PanelModel(store: AgentStore(api: api), api: api)
    model.drafts["w1:p1"] = " use main \n"
    await model.reply(for: "w1:p1")
    #expect(api.texts == [Call(pane: "w1:p1", value: "use main")])
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

@MainActor @Test func successfulChoiceIsMarkedAnsweredThenCleared() async {
    let api = FakeAPI()
    api.agents = [agent("w1:p1", .blocked)]
    let model = PanelModel(store: AgentStore(api: api), api: api, answeredDuration: .milliseconds(50))
    await model.choose(1, for: "w1:p1")
    #expect(model.answered.contains("w1:p1"))
    #expect(await eventually { !model.answered.contains("w1:p1") })
}

@MainActor @Test func failedChoiceIsNotMarkedAnswered() async {
    let api = FakeAPI()
    api.agents = [agent("w1:p1", .working)]
    let model = PanelModel(store: AgentStore(api: api), api: api)
    await model.choose(1, for: "w1:p1")
    #expect(model.answered.isEmpty)
}

@MainActor @Test func answeredCardStaysWhileAgentStartsWorking() async {
    let api = FakeAPI()
    api.agents = [agent("w1:p1", .blocked), agent("w1:p2", .idle)]
    let store = AgentStore(api: api)
    await store.refresh()
    let model = PanelModel(store: store, api: api, answeredDuration: .milliseconds(80))
    await model.choose(1, for: "w1:p1")
    store.apply(.statusChanged(paneID: "w1:p1", status: .working))
    #expect(model.cards.map(\.paneID) == ["w1:p1"])
    #expect(model.rows.map(\.paneID) == ["w1:p2"])
    #expect(await eventually { model.cards.isEmpty })
    #expect(model.rows.map(\.paneID) == ["w1:p1", "w1:p2"])
}

@MainActor private func shortcutModel(_ agents: [Agent], screen: String) async -> (PanelModel, FakeAPI) {
    let api = FakeAPI()
    api.agents = agents
    api.screenText = screen
    let store = AgentStore(api: api)
    await store.refresh()
    let model = PanelModel(store: store, api: api)
    for agent in agents { await model.reload(agent.paneID) }
    return (model, api)
}

private let menu = "Which file?\n❯ 1. red.txt\n  2. blue.txt\n  3. green.txt"

@MainActor @Test func digitKeyTargetsFirstWaitingCard() async {
    let (model, _) = await shortcutModel([agent("w1:p1", .blocked), agent("w1:p2", .blocked)], screen: menu)
    #expect(model.shortcutTarget(for: 2) == "w1:p1")
}

@MainActor @Test func digitKeyTargetsHoveredCard() async {
    let (model, _) = await shortcutModel([agent("w1:p1", .blocked), agent("w1:p2", .blocked)], screen: menu)
    model.hoveredCard = "w1:p2"
    #expect(model.shortcutTarget(for: 2) == "w1:p2")
}

@MainActor @Test func digitWithoutMatchingOptionIsIgnored() async {
    let (model, _) = await shortcutModel([agent("w1:p1", .blocked)], screen: menu)
    #expect(model.shortcutTarget(for: 7) == nil)
}

@MainActor @Test func answeredCardIsNotAShortcutTarget() async {
    let (model, _) = await shortcutModel([agent("w1:p1", .blocked)], screen: menu)
    await model.choose(1, for: "w1:p1")
    #expect(model.shortcutTarget(for: 2) == nil)
}

@MainActor @Test func choiceMarksPendingOptionUntilDone() async {
    let (model, api) = await shortcutModel([agent("w1:p1", .blocked)], screen: menu)
    await model.choose(3, for: "w1:p1")
    #expect(api.sentKeys == [Call(pane: "w1:p1", value: "3")])
    #expect(model.pendingOption["w1:p1"] == nil)
}

@MainActor @Test func hoverShowsSummariesWhenOnlyFinishedAgents() async {
    let api = FakeAPI()
    var done = agent("w1:p1", .done); done.completion = 5
    api.agents = [done, agent("w1:p2", .working)]
    let store = AgentStore(api: api)
    await store.refresh()
    let model = PanelModel(store: store, api: api) { _ in nil }
    #expect(model.mode == .finished)
    model.showAll = true
    #expect(model.mode == .all)
}

@MainActor @Test func waitingAgentAlwaysShowsFullPanel() async {
    let api = FakeAPI()
    var done = agent("w1:p1", .done); done.completion = 5
    api.agents = [done, agent("w1:p2", .blocked)]
    let store = AgentStore(api: api)
    await store.refresh()
    #expect(PanelModel(store: store, api: api) { _ in nil }.mode == .all)
}

@MainActor @Test func closingAfterFinishedSummariesMarksThemSeen() async {
    let api = FakeAPI()
    var done = agent("w1:p1", .done); done.completion = 5; done.sessionID = "abc-123"
    api.agents = [done]
    let store = AgentStore(api: api)
    await store.refresh()
    let model = PanelModel(store: store, api: api) { _ in TranscriptSummary(lastMessage: "Done") }
    await model.panelOpened()
    #expect(model.summaries["w1:p1"]?.lastMessage == "Done")
    model.showAll = true
    model.panelClosed()
    #expect(store.color == .calm)
    #expect(model.showAll == false)
}

@MainActor @Test func closingFullPanelDoesNotMarkSeen() async {
    let api = FakeAPI()
    var done = agent("w1:p1", .done); done.completion = 5
    api.agents = [done, agent("w1:p2", .blocked)]
    let store = AgentStore(api: api)
    await store.refresh()
    let model = PanelModel(store: store, api: api) { _ in nil }
    await model.panelOpened()
    model.panelClosed()
    #expect(store.finished.map(\.paneID) == ["w1:p1"])
}

@Test func nextTaskGoesToFinishedOrIdleAgent() async throws {
    let api = FakeAPI()
    api.agents = [agent("w1:p1", .done), agent("w1:p2", .idle)]
    try await AnswerService(api: api).nextTask(text: "add tests", paneID: "w1:p1")
    try await AnswerService(api: api).nextTask(text: "ship it", paneID: "w1:p2")
    #expect(api.prompts == [Call(pane: "w1:p1", value: "add tests"), Call(pane: "w1:p2", value: "ship it")])
}

@Test func nextTaskRefusedWhileAgentWaitsOrWorks() async {
    let api = FakeAPI()
    api.agents = [agent("w1:p1", .blocked), agent("w1:p2", .working)]
    for pane in ["w1:p1", "w1:p2"] {
        await #expect(throws: AnswerError.agentBusy) {
            try await AnswerService(api: api).nextTask(text: "hi", paneID: pane)
        }
    }
    #expect(api.prompts.isEmpty)
}

@MainActor @Test func sendNextTrimsClearsDraftAndKeepsFinishedCardOpen() async {
    let api = FakeAPI()
    var done = agent("w1:p1", .done); done.completion = 5
    api.agents = [done]
    let store = AgentStore(api: api)
    await store.refresh()
    let model = PanelModel(store: store, api: api) { _ in nil }
    await model.panelOpened()
    model.drafts["w1:p1"] = "  next step \n"
    await model.sendNext(for: "w1:p1")
    #expect(api.prompts == [Call(pane: "w1:p1", value: "next step")])
    #expect(model.drafts["w1:p1"] == nil)
    #expect(model.sentNext.contains("w1:p1"))
    store.apply(.statusChanged(paneID: "w1:p1", status: .working))
    #expect(model.mode == .finished)
    #expect(model.finishedAgents.map(\.paneID) == ["w1:p1"])
}

@MainActor @Test func blankNextTaskSendsNothing() async {
    let api = FakeAPI()
    api.agents = [agent("w1:p1", .done)]
    let model = PanelModel(store: AgentStore(api: api), api: api) { _ in nil }
    model.drafts["w1:p1"] = "   "
    await model.sendNext(for: "w1:p1")
    #expect(api.prompts.isEmpty)
}
