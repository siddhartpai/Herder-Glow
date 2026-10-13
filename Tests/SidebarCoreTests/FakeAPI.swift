import Foundation
@testable import SidebarCore

struct Call: Equatable {
    let pane: String
    let value: String
}

final class FakeSubscription: HerdrSubscription, @unchecked Sendable {
    var cancelled = false
    func cancel() { cancelled = true }
}

final class FakeAPI: HerdrAPI, @unchecked Sendable {
    var agents: [Agent] = []
    var listError: Error?
    var listCalls = 0
    var screenText = ""
    var sendError: Error?
    var sentKeys: [Call] = []
    var texts: [Call] = []
    var prompts: [Call] = []
    var focused: [String] = []
    private(set) var subscribedPaneIDs: [String] = []
    private(set) var subscriptions: [FakeSubscription] = []
    private var onEvent: (@Sendable (HerdrEvent) -> Void)?
    private var onClose: (@Sendable (Error) -> Void)?

    func listAgents() async throws -> [Agent] {
        listCalls += 1
        if let listError { throw listError }
        return agents
    }

    func getAgent(_ paneID: String) async throws -> Agent {
        guard let agent = agents.first(where: { $0.paneID == paneID }) else {
            throw HerdrError.server(code: "agent_not_found", message: "agent target \(paneID) not found")
        }
        return agent
    }

    func read(_ paneID: String, lines: Int) async throws -> String { screenText }

    func sendKeys(_ paneID: String, _ keys: [String]) async throws {
        if let sendError { throw sendError }
        sentKeys.append(Call(pane: paneID, value: keys.joined(separator: " ")))
    }

    func sendText(_ paneID: String, _ text: String) async throws {
        if let sendError { throw sendError }
        texts.append(Call(pane: paneID, value: text))
    }

    func prompt(_ paneID: String, _ text: String) async throws {
        if let sendError { throw sendError }
        prompts.append(Call(pane: paneID, value: text))
    }

    func focus(_ paneID: String) async throws { focused.append(paneID) }

    func subscribe(paneIDs: [String],
                   onEvent: @escaping @Sendable (HerdrEvent) -> Void,
                   onClose: @escaping @Sendable (Error) -> Void) -> HerdrSubscription {
        subscribedPaneIDs = paneIDs
        self.onEvent = onEvent
        self.onClose = onClose
        let subscription = FakeSubscription()
        subscriptions.append(subscription)
        return subscription
    }

    func emit(_ event: HerdrEvent) { onEvent?(event) }
    func close(_ error: Error) { onClose?(error) }
}
