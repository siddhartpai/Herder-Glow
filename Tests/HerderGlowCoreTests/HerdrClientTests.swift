import Testing
import Foundation
@testable import HerderGlowCore

@Test func listAgentsParsesAgentList() async throws {
    let server = try FakeHerdrServer { _ in [
        #"{"id":"1","result":{"type":"agent_list","agents":[{"pane_id":"w1:p1","agent_status":"blocked","terminal_title_stripped":"Fix bug","cwd":"/tmp/a"}]}}"#,
    ] }
    defer { server.stop() }
    let agents = try await HerdrClient(socketPath: server.path).listAgents()
    #expect(agents == [Agent(paneID: "w1:p1", title: "Fix bug", cwd: "/tmp/a", status: .blocked)])
    #expect(server.requests.first?["method"] as? String == "agent.list")
}

@Test func serverErrorIsThrown() async throws {
    let server = try FakeHerdrServer { _ in [
        #"{"id":"1","error":{"code":"agent_not_found","message":"agent target w9:p9 not found"}}"#,
    ] }
    defer { server.stop() }
    await #expect(throws: HerdrError.server(code: "agent_not_found", message: "agent target w9:p9 not found")) {
        try await HerdrClient(socketPath: server.path).getAgent("w9:p9")
    }
}

@Test func readRequestsVisibleScreen() async throws {
    let server = try FakeHerdrServer { _ in [
        #"{"id":"1","result":{"type":"pane_read","read":{"pane_id":"w1:p1","text":"Do you want to proceed?"}}}"#,
    ] }
    defer { server.stop() }
    let text = try await HerdrClient(socketPath: server.path).read("w1:p1", lines: 20)
    #expect(text == "Do you want to proceed?")
    let params = server.requests.first?["params"] as? [String: Any]
    #expect(server.requests.first?["method"] as? String == "agent.read")
    #expect(params?["target"] as? String == "w1:p1")
    #expect(params?["source"] as? String == "visible")
    #expect(params?["lines"] as? Int == 20)
}

@Test func sendKeysSendsKeyList() async throws {
    let server = try FakeHerdrServer { _ in [#"{"id":"1","result":{"type":"ok"}}"#] }
    defer { server.stop() }
    try await HerdrClient(socketPath: server.path).sendKeys("w1:p1", ["2"])
    let params = server.requests.first?["params"] as? [String: Any]
    #expect(server.requests.first?["method"] as? String == "agent.send_keys")
    #expect(params?["keys"] as? [String] == ["2"])
}

@Test func missingSocketThrowsSocketError() async {
    let error = await #expect(throws: HerdrError.self) {
        try await HerdrClient(socketPath: "/tmp/does-not-exist.sock").listAgents()
    }
    guard case .socket = error else {
        Issue.record("expected a socket error, got \(String(describing: error))")
        return
    }
}

@Test func promptSendsAgentPrompt() async throws {
    let server = try FakeHerdrServer { _ in [#"{"id":"1","result":{"type":"ok"}}"#] }
    defer { server.stop() }
    try await HerdrClient(socketPath: server.path).prompt("w1:p1", "add tests")
    let params = server.requests.first?["params"] as? [String: Any]
    #expect(server.requests.first?["method"] as? String == "agent.prompt")
    #expect(params?["target"] as? String == "w1:p1")
    #expect(params?["text"] as? String == "add tests")
}
