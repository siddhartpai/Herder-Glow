import Testing
import Foundation
@testable import SidebarCore

@Test func parsesStatusChangedEvent() {
    let event = HerdrEvent.parse([
        "event": "pane.agent_status_changed",
        "data": ["pane_id": "w1:p1", "workspace_id": "w1", "agent_status": "blocked"],
    ])
    #expect(event == .statusChanged(paneID: "w1:p1", status: .blocked))
}

@Test func paneLifecycleEventsAreTopologyChanges() {
    for name in ["pane.created", "pane.closed", "pane.exited", "pane.agent_detected"] {
        #expect(HerdrEvent.parse(["event": name, "data": [:]]) == .topologyChanged)
    }
}

@Test func otherEventsAreIgnored() {
    #expect(HerdrEvent.parse(["event": "pane.scroll_changed", "data": [:]]) == nil)
    #expect(HerdrEvent.parse(["id": "1", "result": ["type": "subscription_started"]]) == nil)
}

@MainActor @Test func subscribeDeliversEventsThenReportsClose() async throws {
    let server = try FakeHerdrServer { _ in [
        #"{"id":"sub","result":{"type":"subscription_started"}}"#,
        #"{"event":"pane.agent_status_changed","data":{"pane_id":"w1:p1","workspace_id":"w1","agent_status":"working"}}"#,
    ] }
    defer { server.stop() }
    let events = Box<[HerdrEvent]>([])
    let closed = Box(false)
    let sub = HerdrClient(socketPath: server.path).subscribe(
        paneIDs: ["w1:p1"],
        onEvent: { events.value.append($0) },
        onClose: { _ in closed.value = true })
    #expect(await eventually { closed.value })
    #expect(events.value == [.statusChanged(paneID: "w1:p1", status: .working)])
    let params = server.requests.first?["params"] as? [String: Any]
    let subs = params?["subscriptions"] as? [[String: String]] ?? []
    #expect(server.requests.first?["method"] as? String == "events.subscribe")
    #expect(subs.contains(["type": "pane.agent_status_changed", "pane_id": "w1:p1"]))
    #expect(subs.contains(["type": "pane.created"]))
    sub.cancel()
}

@MainActor @Test func cancelDoesNotReportClose() async throws {
    let server = try FakeHerdrServer(holdOpen: 2) { _ in [
        #"{"id":"sub","result":{"type":"subscription_started"}}"#,
    ] }
    defer { server.stop() }
    let closed = Box(false)
    let sub = HerdrClient(socketPath: server.path).subscribe(
        paneIDs: [], onEvent: { _ in }, onClose: { _ in closed.value = true })
    try await Task.sleep(for: .milliseconds(200))
    sub.cancel()
    try await Task.sleep(for: .milliseconds(300))
    #expect(closed.value == false)
}
