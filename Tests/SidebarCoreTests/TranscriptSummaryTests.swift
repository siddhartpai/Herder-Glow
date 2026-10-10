import Testing
import Foundation
@testable import SidebarCore

private func line(_ object: [String: Any]) -> String {
    String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
}

private func user(_ text: String) -> String {
    line(["type": "user", "message": ["role": "user", "content": text]])
}

private func assistant(_ content: [[String: Any]]) -> String {
    line(["type": "assistant", "message": ["role": "assistant", "content": content]])
}

private func tool(_ name: String, _ input: [String: Any]) -> [String: Any] {
    ["type": "tool_use", "name": name, "input": input]
}

@Test func summaryCollectsTitleRequestFilesCommandsAndLastMessage() {
    let lines = [
        user("Add a login page"),
        assistant([tool("Write", ["file_path": "/app/Login.swift", "content": "x"])]),
        line(["type": "ai-title", "aiTitle": "Login page"]),
        user("Now add tests"),
        assistant([tool("Bash", ["command": "swift test"]), tool("Edit", ["file_path": "/app/LoginTests.swift"])]),
        assistant([tool("Edit", ["file_path": "/app/Login.swift"]), tool("Bash", ["command": "git status"])]),
        assistant([["type": "text", "text": "Done: tests pass.\nAll 4 tests are green."]]),
    ]
    let summary = TranscriptSummary.parse(lines: lines)
    #expect(summary.title == "Login page")
    #expect(summary.lastRequest == "Now add tests")
    #expect(summary.filesChanged == ["/app/LoginTests.swift", "/app/Login.swift"])
    #expect(summary.commandCount == 2)
    #expect(summary.lastMessage == "Done: tests pass.\nAll 4 tests are green.")
}

@Test func toolResultsAndSystemTextAreNotRequests() {
    let lines = [
        user("Fix the bug"),
        line(["type": "user", "message": ["role": "user", "content": [["type": "tool_result", "content": "ok"]]]]),
        user("<system-reminder>context</system-reminder>"),
        line(["type": "user", "message": ["role": "user", "content": [["type": "text", "text": "<command-name>/clear</command-name>"]]]]),
    ]
    #expect(TranscriptSummary.parse(lines: lines).lastRequest == "Fix the bug")
}

@Test func textBlockRequestIsRead() {
    let lines = [line(["type": "user", "message": ["role": "user", "content": [["type": "text", "text": "Ship it"]]]])]
    #expect(TranscriptSummary.parse(lines: lines).lastRequest == "Ship it")
}

@Test func brokenLinesAreSkipped() {
    let summary = TranscriptSummary.parse(lines: ["{not json", user("Hello"), ""])
    #expect(summary.lastRequest == "Hello")
    #expect(summary.filesChanged.isEmpty)
}

@Test func transcriptIsFoundInAnyProjectFolder() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let folder = root.appendingPathComponent("-Users-me-app")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appendingPathComponent("abc-123.jsonl")
    try (user("Hi") + "\n").write(to: file, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(TranscriptSummary.locate(sessionID: "abc-123", projectsDir: root)?.resolvingSymlinksInPath() == file.resolvingSymlinksInPath())
    #expect(TranscriptSummary.locate(sessionID: "missing", projectsDir: root) == nil)
    #expect(TranscriptSummary.load(sessionID: "abc-123", projectsDir: root)?.lastRequest == "Hi")
}

@Test func claudeSessionIDIsReadFromAgentInfo() {
    let info: [String: Any] = ["pane_id": "w1:p1", "agent_status": "idle", "agent": "claude",
                               "agent_session": ["agent": "claude", "kind": "id", "value": "abc-123"]]
    #expect(Agent(json: info)?.sessionID == "abc-123")
    var path = info
    path["agent_session"] = ["agent": "claude", "kind": "path", "value": "/x"]
    #expect(Agent(json: path)?.sessionID == nil)
}

@MainActor @Test func toggleSummaryLoadsAndCollapses() async {
    let api = FakeAPI()
    var claude = agent("w1:p1", .done)
    claude.sessionID = "abc-123"
    api.agents = [claude]
    let store = AgentStore(api: api)
    await store.refresh()
    let model = PanelModel(store: store, api: api) { sessionID in
        sessionID == "abc-123" ? TranscriptSummary(title: "T", lastRequest: "R") : nil
    }
    await model.toggleSummary("w1:p1")
    #expect(model.expanded == "w1:p1")
    #expect(model.summaries["w1:p1"]?.lastRequest == "R")
    await model.toggleSummary("w1:p1")
    #expect(model.expanded == nil)
}

@MainActor @Test func agentWithoutSessionGetsScreenText() async {
    let api = FakeAPI()
    api.agents = [agent("w1:p1", .idle)]
    api.screenText = "last output"
    let store = AgentStore(api: api)
    await store.refresh()
    let model = PanelModel(store: store, api: api) { _ in nil }
    await model.toggleSummary("w1:p1")
    #expect(model.summaries["w1:p1"] == nil)
    #expect(model.screens["w1:p1"] == "last output")
}

private final class Counter: @unchecked Sendable {
    var value = 0
}

@MainActor @Test func openSummaryIsReloadedWhenPanelOpensAgain() async {
    let api = FakeAPI()
    var claude = agent("w1:p1", .working)
    claude.sessionID = "abc-123"
    api.agents = [claude]
    let store = AgentStore(api: api)
    await store.refresh()
    let loads = Counter()
    let model = PanelModel(store: store, api: api) { _ in
        loads.value += 1
        return TranscriptSummary(lastMessage: "message \(loads.value)")
    }
    await model.toggleSummary("w1:p1")
    #expect(model.summaries["w1:p1"]?.lastMessage == "message 1")
    await model.panelOpened()
    #expect(model.summaries["w1:p1"]?.lastMessage == "message 2")
    await model.refreshSummary("w1:p1")
    #expect(model.summaries["w1:p1"]?.lastMessage == "message 3")
}

@MainActor @Test func refreshSkipsClosedRows() async {
    let api = FakeAPI()
    var claude = agent("w1:p1", .done)
    claude.sessionID = "abc-123"
    api.agents = [claude]
    let store = AgentStore(api: api)
    await store.refresh()
    let loads = Counter()
    let model = PanelModel(store: store, api: api) { _ in
        loads.value += 1
        return TranscriptSummary(lastMessage: "m")
    }
    await model.panelOpened()
    await model.refreshSummary("w1:p1")
    #expect(loads.value == 0)
}
