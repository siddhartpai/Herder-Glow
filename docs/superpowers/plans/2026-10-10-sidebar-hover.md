# SidebarHover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS app that shows a traffic light on the right screen edge for all herdr agents, and a hover panel to answer or approve blocked agents.

**Architecture:** A Swift Package with two targets. `SidebarCore` (Foundation + Observation only) holds the herdr socket client, the models, the prompt parser, the agent store and the panel model; all of it is unit-tested. `SidebarHover` (AppKit + SwiftUI) holds the edge window, the hover panel and the menu bar item; it is tested by hand.

**Tech Stack:** Swift 6.2 toolchain (Swift 5 language mode), AppKit, SwiftUI, Observation, ServiceManagement, Swift Testing, POSIX Unix sockets.

**Spec:** `docs/superpowers/specs/2026-10-10-sidebar-hover-design.md`

## Global Constraints

- Platform: macOS 14 or later (`platforms: [.macOS(.v14)]`).
- No third-party dependencies.
- Socket path: `$HERDR_SOCKET_PATH`, else `~/.config/herdr/herdr.sock`.
- Wire format (confirmed live on 2026-10-10): one JSON object per line. Request `{"id","method","params"}`. Response `{"id","result":{...}}` or `{"id","error":{"code","message"}}`. Subscription events: `{"event":"pane.agent_status_changed","data":{...}}`.
- `pane.agent_status_changed` subscriptions need a `pane_id`; `pane.created`, `pane.closed`, `pane.exited`, `pane.agent_detected` do not.
- Light: grey if not connected; red if any `blocked`; else yellow if any `working`; else green.
- Light window: about 14 × 48 px, vertical center of the right edge of the primary screen, all Spaces, over full-screen apps.
- Panel: 380 px wide, max 560 px high, opens left of the light, closes 0.3 s after the mouse leaves both windows.
- Screen text: `agent.read` with `source: "recent"`, `lines: 20`.
- Safety rule: never send keys or text to an agent whose current status (from `agent.get`) is not `blocked`.
- Reconnect delay: 2 s.
- Bundle id: `dev.sid.sidebarhover`. App path: `~/Applications/SidebarHover.app`. `LSUIElement` true.

## Review Focus

1. Agent leaves `blocked` between hover and click → nothing is sent, panel shows "Prompt changed" and new screen text. Pinned in Task 6 (`choiceRefusedWhenAgentNoLongerBlocked`, `promptChangedShowsMessageAndReloads`).
2. herdr not running at launch, or herdr restarts → grey light, then automatic recovery. Pinned in Task 5 (`listFailureShowsGreyThenRecovers`, `subscriptionCloseTriggersReconnect`).
3. Earlier output contains a numbered list above the real prompt → only the last numbered run (starting at 1) becomes buttons. Pinned in Task 2 (`earlierNumberedListIsIgnored`).
4. Prompt drawn inside a box with `│` borders and a `❯` cursor → clean labels. Pinned in Task 2 (`boxedPermissionPrompt`).
5. Empty or whitespace-only text reply → nothing is sent. Pinned in Task 6 (`blankReplySendsNothing`).

Known limit (accepted for v1): when a blocked agent asks a free-text question that contains a numbered list, the buttons send only the digit with no Enter. The text box still works.

## File Structure

```
Package.swift
Sources/SidebarCore/
  Models.swift          Agent, AgentStatus, LightColor
  PromptParser.swift    PromptOption, PromptParser
  HerdrError.swift      HerdrError
  LineSocket.swift      Unix socket with line framing, withUnixAddress helper
  HerdrClient.swift     HerdrAPI protocol, HerdrSubscription protocol, HerdrClient
  HerdrEvent.swift      HerdrEvent and its JSON parser
  AgentStore.swift      Observable agent list, light color, reconnect
  AnswerService.swift   Safety-checked send of option keys and text
  PanelModel.swift      Observable state for the hover panel
Sources/SidebarHover/
  main.swift            App entry
  AppDelegate.swift     Wires store, windows, menu bar item
  TrackingView.swift    NSView that reports mouse enter/exit
  EdgeLightWindow.swift Edge window + LightView
  HoverPanel.swift      HoverPanel window + HoverController
  PanelViews.swift      SwiftUI panel content
Resources/Info.plist
scripts/bundle.sh
Tests/SidebarCoreTests/
  ModelsTests.swift
  PromptParserTests.swift
  TestSupport.swift     FakeHerdrServer, Box, eventually, agent()
  HerdrClientTests.swift
  HerdrEventTests.swift
  FakeAPI.swift
  AgentStoreTests.swift
  AnswerTests.swift
```

---

### Task 1: Package and models

**Files:**
- Create: `Package.swift`
- Create: `Sources/SidebarCore/Models.swift`
- Test: `Tests/SidebarCoreTests/ModelsTests.swift`

**Interfaces:**
- Produces: `public enum AgentStatus: String { idle, working, blocked, done, unknown }`; `public struct Agent: Identifiable, Equatable, Sendable { paneID, title, cwd, status; init(paneID:title:cwd:status:); init?(json: [String: Any]) }`; `public enum LightColor { grey, red, yellow, green; static func compute(connected: Bool, agents: [Agent]) -> LightColor }`.

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SidebarHover",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SidebarCore"),
        .testTarget(name: "SidebarCoreTests", dependencies: ["SidebarCore"]),
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 2: Write the failing tests** — `Tests/SidebarCoreTests/ModelsTests.swift`

```swift
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

@Test func yellowWhenWorkingAndNoneBlocked() {
    #expect(LightColor.compute(connected: true, agents: agents(.working, .done)) == .yellow)
}

@Test func greenWhenAllDoneIdleOrUnknown() {
    #expect(LightColor.compute(connected: true, agents: agents(.done, .idle, .unknown)) == .green)
}

@Test func greenWhenNoAgents() {
    #expect(LightColor.compute(connected: true, agents: []) == .green)
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test`
Expected: build FAIL — `cannot find 'Agent' in scope`.

- [ ] **Step 4: Write the implementation** — `Sources/SidebarCore/Models.swift`

```swift
import Foundation

public enum AgentStatus: String, Sendable {
    case idle, working, blocked, done, unknown
}

public struct Agent: Identifiable, Equatable, Sendable {
    public var paneID: String
    public var title: String
    public var cwd: String
    public var status: AgentStatus
    public var id: String { paneID }

    public init(paneID: String, title: String, cwd: String, status: AgentStatus) {
        self.paneID = paneID
        self.title = title
        self.cwd = cwd
        self.status = status
    }

    /// Builds an agent from a herdr `AgentInfo` object.
    init?(json: [String: Any]) {
        guard let paneID = json["pane_id"] as? String,
              let status = json["agent_status"] as? String else { return nil }
        let title = json["terminal_title_stripped"] as? String
        self.paneID = paneID
        self.title = (title?.isEmpty == false ? title : nil) ?? (json["agent"] as? String) ?? paneID
        self.cwd = json["cwd"] as? String ?? ""
        self.status = AgentStatus(rawValue: status) ?? .unknown
    }
}

public enum LightColor: Equatable, Sendable {
    case grey, red, yellow, green

    public static func compute(connected: Bool, agents: [Agent]) -> LightColor {
        guard connected else { return .grey }
        if agents.contains(where: { $0.status == .blocked }) { return .red }
        if agents.contains(where: { $0.status == .working }) { return .yellow }
        return .green
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test`
Expected: 9 tests passed.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/SidebarCore/Models.swift Tests/SidebarCoreTests/ModelsTests.swift
git commit -m "feat: add agent models and light color rules"
```

---

### Task 2: Prompt parser

**Files:**
- Create: `Sources/SidebarCore/PromptParser.swift`
- Test: `Tests/SidebarCoreTests/PromptParserTests.swift`

**Interfaces:**
- Produces: `public struct PromptOption: Equatable, Sendable { number: Int; label: String }`; `public enum PromptParser { static func options(in screen: String) -> [PromptOption] }`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import SidebarCore

@Test func boxedPermissionPrompt() {
    let screen = """
    ╭───────────────────────────────────────────╮
    │ Bash command                              │
    │                                           │
    │   rm -rf build                            │
    │                                           │
    │ Do you want to proceed?                   │
    │ ❯ 1. Yes                                  │
    │   2. Yes, and don't ask again for rm      │
    │   3. No, and tell Claude what to do (esc) │
    ╰───────────────────────────────────────────╯
    """
    #expect(PromptParser.options(in: screen) == [
        PromptOption(number: 1, label: "Yes"),
        PromptOption(number: 2, label: "Yes, and don't ask again for rm"),
        PromptOption(number: 3, label: "No, and tell Claude what to do (esc)"),
    ])
}

@Test func unboxedEditPrompt() {
    let screen = """
     Do you want to make this edit to Package.swift?
     ❯ 1. Yes
       2. Yes, allow all edits during this session (shift+tab)
       3. No, and tell Claude what to do differently (esc)
    """
    #expect(PromptParser.options(in: screen).map(\.number) == [1, 2, 3])
    #expect(PromptParser.options(in: screen)[1].label == "Yes, allow all edits during this session (shift+tab)")
}

@Test func earlierNumberedListIsIgnored() {
    let screen = """
    Plan:
    1. Install deps
    2. Run tests
    3. Ship
    Do you want to proceed?
    ❯ 1. Yes
      2. No
    """
    #expect(PromptParser.options(in: screen) == [
        PromptOption(number: 1, label: "Yes"),
        PromptOption(number: 2, label: "No"),
    ])
}

@Test func freeTextQuestionHasNoOptions() {
    #expect(PromptParser.options(in: "What name should the new branch have?\n> ").isEmpty)
}

@Test func plainOutputHasNoOptions() {
    #expect(PromptParser.options(in: "Running tests…\nAll 12 tests passed.").isEmpty)
}

@Test func singleNumberedLineIsNotAPrompt() {
    #expect(PromptParser.options(in: "1. Only one").isEmpty)
}

@Test func nonSequentialNumbersAreNotAPrompt() {
    #expect(PromptParser.options(in: "1. a\n3. c").isEmpty)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter PromptParser`
Expected: build FAIL — `cannot find 'PromptParser' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

public struct PromptOption: Equatable, Sendable {
    public let number: Int
    public let label: String

    public init(number: Int, label: String) {
        self.number = number
        self.label = label
    }
}

public enum PromptParser {
    /// Returns the last run of options numbered 1, 2, 3… on the screen.
    /// Lines that are not options (wrapped text, box borders) do not end a run.
    public static func options(in screen: String) -> [PromptOption] {
        var run: [PromptOption] = []
        for line in screen.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let option = parseLine(line) else { continue }
            if option.number == 1 {
                run = [option]
            } else if let last = run.last, option.number == last.number + 1 {
                run.append(option)
            } else {
                run = []
            }
        }
        return run.count >= 2 ? run : []
    }

    static func parseLine(_ raw: Substring) -> PromptOption? {
        var text = raw.trimmingCharacters(in: CharacterSet(charactersIn: "│|").union(.whitespaces))
        if let marker = ["❯", "›", ">"].first(where: { text.hasPrefix($0) }) {
            text = String(text.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        let digits = text.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 2, let number = Int(digits) else { return nil }
        let rest = text.dropFirst(digits.count)
        guard rest.hasPrefix(". ") else { return nil }
        let label = rest.dropFirst(2).trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return nil }
        return PromptOption(number: number, label: label)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter PromptParser`
Expected: 7 tests passed.

- [ ] **Step 5: Commit**

```bash
git add Sources/SidebarCore/PromptParser.swift Tests/SidebarCoreTests/PromptParserTests.swift
git commit -m "feat: parse numbered prompt options from screen text"
```

---

### Task 3: Socket and request/response client

**Files:**
- Create: `Sources/SidebarCore/HerdrError.swift`
- Create: `Sources/SidebarCore/LineSocket.swift`
- Create: `Sources/SidebarCore/HerdrClient.swift`
- Create: `Tests/SidebarCoreTests/TestSupport.swift`
- Test: `Tests/SidebarCoreTests/HerdrClientTests.swift`

**Interfaces:**
- Consumes: `Agent(json:)` from Task 1.
- Produces:
  - `public enum HerdrError: Error, Equatable, CustomStringConvertible { socket(String), server(code: String, message: String), badResponse }`
  - `func withUnixAddress<T>(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) throws -> T` (internal)
  - `final class LineSocket { init(path:) throws; writeLine(_ data: Data) throws; readLine() throws -> Data; shutdown(); close() }` (internal)
  - `public protocol HerdrAPI: Sendable` with `listAgents() async throws -> [Agent]`, `getAgent(_ paneID: String) async throws -> Agent`, `read(_ paneID: String, lines: Int) async throws -> String`, `sendKeys(_ paneID: String, _ keys: [String]) async throws`, `prompt(_ paneID: String, _ text: String) async throws`, `focus(_ paneID: String) async throws`
  - `public final class HerdrClient: HerdrAPI { init(socketPath: String = HerdrClient.defaultSocketPath) }`
  - Test helpers: `FakeHerdrServer(holdOpen: TimeInterval = 0, handler: ([String: Any]) -> [String])` with `path`, `requests: [[String: Any]]`, `stop()`; `final class Box<T>` with `value`; `@MainActor func eventually(timeout: Double = 2, _ condition: () -> Bool) async -> Bool`; `func agent(_ paneID: String, _ status: AgentStatus) -> Agent`.

- [ ] **Step 1: Write test support** — `Tests/SidebarCoreTests/TestSupport.swift`

```swift
import Foundation
@testable import SidebarCore

func agent(_ paneID: String, _ status: AgentStatus) -> Agent {
    Agent(paneID: paneID, title: paneID, cwd: "/tmp", status: status)
}

/// Thread-safe value holder for callbacks that run on other threads.
final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

@MainActor
func eventually(timeout: Double = 2, _ condition: () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}

/// Unix-socket server that answers each connection's first line with `handler`'s lines.
final class FakeHerdrServer: @unchecked Sendable {
    let path = "/tmp/shtest-\(UUID().uuidString.prefix(8)).sock"
    private let fd: Int32
    private let handler: ([String: Any]) -> [String]
    private let holdOpen: TimeInterval
    private let received = Box<[[String: Any]]>([])
    var requests: [[String: Any]] { received.value }

    init(holdOpen: TimeInterval = 0, handler: @escaping ([String: Any]) -> [String]) throws {
        self.handler = handler
        self.holdOpen = holdOpen
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        let rc = try withUnixAddress(path) { bind(fd, $0, $1) }
        precondition(rc == 0 && listen(fd, 8) == 0, "fake server failed to listen")
        Thread { [self] in acceptLoop() }.start()
    }

    func stop() {
        Darwin.shutdown(fd, SHUT_RDWR)
        Darwin.close(fd)
        unlink(path)
    }

    private func acceptLoop() {
        while true {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            Thread { [self] in serve(client) }.start()
        }
    }

    private func serve(_ client: Int32) {
        var on: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var line = Data()
        var byte: UInt8 = 0
        while Darwin.read(client, &byte, 1) == 1, byte != 0x0A { line.append(byte) }
        let request = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] ?? [:]
        received.value.append(request)
        for reply in handler(request) {
            let bytes = Array((reply + "\n").utf8)
            _ = Darwin.write(client, bytes, bytes.count)
        }
        if holdOpen > 0 { Thread.sleep(forTimeInterval: holdOpen) }
        Darwin.close(client)
    }
}
```

- [ ] **Step 2: Write the failing tests** — `Tests/SidebarCoreTests/HerdrClientTests.swift`

```swift
import Testing
import Foundation
@testable import SidebarCore

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

@Test func readRequestsRecentTwentyLines() async throws {
    let server = try FakeHerdrServer { _ in [
        #"{"id":"1","result":{"type":"pane_read","read":{"pane_id":"w1:p1","text":"Do you want to proceed?"}}}"#,
    ] }
    defer { server.stop() }
    let text = try await HerdrClient(socketPath: server.path).read("w1:p1", lines: 20)
    #expect(text == "Do you want to proceed?")
    let params = server.requests.first?["params"] as? [String: Any]
    #expect(server.requests.first?["method"] as? String == "agent.read")
    #expect(params?["target"] as? String == "w1:p1")
    #expect(params?["source"] as? String == "recent")
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
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter HerdrClient`
Expected: build FAIL — `cannot find 'withUnixAddress' in scope`.

- [ ] **Step 4: Write `Sources/SidebarCore/HerdrError.swift`**

```swift
import Foundation

public enum HerdrError: Error, Equatable, CustomStringConvertible {
    case socket(String)
    case server(code: String, message: String)
    case badResponse

    public var description: String {
        switch self {
        case .socket(let reason): "herdr connection: \(reason)"
        case .server(_, let message): message
        case .badResponse: "Unexpected response from herdr"
        }
    }

    /// Returns the error in a herdr `{"error": {...}}` response, or nil.
    init?(response: [String: Any]) {
        guard let error = response["error"] as? [String: Any] else { return nil }
        self = .server(code: error["code"] as? String ?? "unknown",
                       message: error["message"] as? String ?? "")
    }
}
```

- [ ] **Step 5: Write `Sources/SidebarCore/LineSocket.swift`**

```swift
import Foundation

func withUnixAddress<T>(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) throws -> T {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
        throw HerdrError.socket("socket path too long: \(path)")
    }
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
    return withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
}

/// A connected Unix socket that sends and receives newline-terminated messages.
final class LineSocket: @unchecked Sendable {
    private let fd: Int32
    private var buffer = Data()

    init(path: String) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw HerdrError.socket("socket() failed") }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let rc: Int32
        do {
            rc = try withUnixAddress(path) { connect(fd, $0, $1) }
        } catch {
            Darwin.close(fd)
            throw error
        }
        guard rc == 0 else {
            let reason = String(cString: strerror(errno))
            Darwin.close(fd)
            throw HerdrError.socket("cannot connect to \(path): \(reason)")
        }
        self.fd = fd
    }

    func writeLine(_ data: Data) throws {
        var payload = data
        payload.append(0x0A)
        try payload.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var offset = 0
            while offset < raw.count {
                let written = Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset)
                guard written > 0 else { throw HerdrError.socket("write failed") }
                offset += written
            }
        }
    }

    func readLine() throws -> Data {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<newline)
                buffer.removeSubrange(buffer.startIndex...newline)
                return line
            }
            var chunk = [UInt8](repeating: 0, count: 65536)
            let count = Darwin.read(fd, &chunk, chunk.count)
            guard count > 0 else { throw HerdrError.socket("connection closed") }
            buffer.append(chunk, count: count)
        }
    }

    /// Unblocks a pending `readLine()` on another thread.
    func shutdown() { _ = Darwin.shutdown(fd, SHUT_RDWR) }

    func close() { _ = Darwin.close(fd) }
}
```

- [ ] **Step 6: Write `Sources/SidebarCore/HerdrClient.swift`**

```swift
import Foundation

public protocol HerdrAPI: Sendable {
    func listAgents() async throws -> [Agent]
    func getAgent(_ paneID: String) async throws -> Agent
    func read(_ paneID: String, lines: Int) async throws -> String
    func sendKeys(_ paneID: String, _ keys: [String]) async throws
    func prompt(_ paneID: String, _ text: String) async throws
    func focus(_ paneID: String) async throws
}

/// Talks to the herdr server over its Unix socket. One connection per request.
public final class HerdrClient: HerdrAPI {
    public let socketPath: String

    public init(socketPath: String = HerdrClient.defaultSocketPath) {
        self.socketPath = socketPath
    }

    public static var defaultSocketPath: String {
        ProcessInfo.processInfo.environment["HERDR_SOCKET_PATH"]
            ?? NSHomeDirectory() + "/.config/herdr/herdr.sock"
    }

    public func listAgents() async throws -> [Agent] {
        let result = try await call("agent.list", [:])
        let list = result["agents"] as? [[String: Any]] ?? []
        return list.compactMap(Agent.init(json:))
    }

    public func getAgent(_ paneID: String) async throws -> Agent {
        let result = try await call("agent.get", ["target": paneID])
        guard let json = result["agent"] as? [String: Any], let agent = Agent(json: json) else {
            throw HerdrError.badResponse
        }
        return agent
    }

    public func read(_ paneID: String, lines: Int) async throws -> String {
        let result = try await call("agent.read", ["target": paneID, "source": "recent", "lines": lines])
        guard let read = result["read"] as? [String: Any], let text = read["text"] as? String else {
            throw HerdrError.badResponse
        }
        return text
    }

    public func sendKeys(_ paneID: String, _ keys: [String]) async throws {
        _ = try await call("agent.send_keys", ["target": paneID, "keys": keys])
    }

    public func prompt(_ paneID: String, _ text: String) async throws {
        _ = try await call("agent.prompt", ["target": paneID, "text": text])
    }

    public func focus(_ paneID: String) async throws {
        _ = try await call("agent.focus", ["target": paneID])
    }

    private func call(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        let path = socketPath
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try Self.callSync(path: path, method: method, params: params))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func callSync(path: String, method: String, params: [String: Any]) throws -> [String: Any] {
        let socket = try LineSocket(path: path)
        defer { socket.close() }
        let request: [String: Any] = ["id": UUID().uuidString, "method": method, "params": params]
        try socket.writeLine(JSONSerialization.data(withJSONObject: request))
        guard let response = try JSONSerialization.jsonObject(with: socket.readLine()) as? [String: Any] else {
            throw HerdrError.badResponse
        }
        if let error = HerdrError(response: response) { throw error }
        guard let result = response["result"] as? [String: Any] else { throw HerdrError.badResponse }
        return result
    }
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `swift test --filter HerdrClient`
Expected: 5 tests passed.

- [ ] **Step 8: Commit**

```bash
git add Sources/SidebarCore/HerdrError.swift Sources/SidebarCore/LineSocket.swift Sources/SidebarCore/HerdrClient.swift Tests/SidebarCoreTests/TestSupport.swift Tests/SidebarCoreTests/HerdrClientTests.swift
git commit -m "feat: add herdr socket client for agent requests"
```

---

### Task 4: Event subscription

**Files:**
- Create: `Sources/SidebarCore/HerdrEvent.swift`
- Modify: `Sources/SidebarCore/HerdrClient.swift` (add protocol requirement and `subscribe`)
- Test: `Tests/SidebarCoreTests/HerdrEventTests.swift`

**Interfaces:**
- Consumes: `LineSocket`, `HerdrError(response:)`, `FakeHerdrServer`, `Box`, `eventually` from Task 3.
- Produces:
  - `public enum HerdrEvent: Equatable, Sendable { statusChanged(paneID: String, status: AgentStatus), topologyChanged; static func parse(_ object: [String: Any]) -> HerdrEvent? }`
  - `public protocol HerdrSubscription: AnyObject, Sendable { func cancel() }`
  - New `HerdrAPI` requirement: `func subscribe(paneIDs: [String], onEvent: @escaping @Sendable (HerdrEvent) -> Void, onClose: @escaping @Sendable (Error) -> Void) -> HerdrSubscription`. `onClose` is not called after `cancel()`.

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter HerdrEvent`
Expected: build FAIL — `cannot find 'HerdrEvent' in scope`.

- [ ] **Step 3: Write `Sources/SidebarCore/HerdrEvent.swift`**

```swift
import Foundation

public enum HerdrEvent: Equatable, Sendable {
    case statusChanged(paneID: String, status: AgentStatus)
    /// A pane or agent appeared or went away; the agent list must be reloaded.
    case topologyChanged

    static let topologyEvents = ["pane.created", "pane.closed", "pane.exited", "pane.agent_detected"]

    public static func parse(_ object: [String: Any]) -> HerdrEvent? {
        guard let name = object["event"] as? String else { return nil }
        let data = object["data"] as? [String: Any] ?? [:]
        if name == "pane.agent_status_changed" {
            guard let paneID = data["pane_id"] as? String,
                  let status = data["agent_status"] as? String else { return nil }
            return .statusChanged(paneID: paneID, status: AgentStatus(rawValue: status) ?? .unknown)
        }
        return topologyEvents.contains(name) ? .topologyChanged : nil
    }
}
```

- [ ] **Step 4: Add subscription to `Sources/SidebarCore/HerdrClient.swift`**

Add to the `HerdrAPI` protocol, after `focus`:

```swift
    func subscribe(paneIDs: [String],
                   onEvent: @escaping @Sendable (HerdrEvent) -> Void,
                   onClose: @escaping @Sendable (Error) -> Void) -> HerdrSubscription
```

Add above `public protocol HerdrAPI`:

```swift
public protocol HerdrSubscription: AnyObject, Sendable {
    func cancel()
}
```

Add inside `HerdrClient`, after `focus`:

```swift
    /// Opens a long-lived connection for events. `onClose` is not called after `cancel()`.
    public func subscribe(paneIDs: [String],
                          onEvent: @escaping @Sendable (HerdrEvent) -> Void,
                          onClose: @escaping @Sendable (Error) -> Void) -> HerdrSubscription {
        let subscription = SocketSubscription()
        let path = socketPath
        let subscriptions = HerdrEvent.topologyEvents.map { ["type": $0] }
            + paneIDs.map { ["type": "pane.agent_status_changed", "pane_id": $0] }
        let request: [String: Any] = ["id": "sub", "method": "events.subscribe",
                                      "params": ["subscriptions": subscriptions]]
        Thread {
            do {
                let socket = try LineSocket(path: path)
                defer { subscription.detach(); socket.close() }
                guard subscription.attach(socket) else { return }
                try socket.writeLine(JSONSerialization.data(withJSONObject: request))
                let started = try JSONSerialization.jsonObject(with: socket.readLine()) as? [String: Any] ?? [:]
                if let error = HerdrError(response: started) { throw error }
                while true {
                    let line = try socket.readLine()
                    if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                       let event = HerdrEvent.parse(object) {
                        onEvent(event)
                    }
                }
            } catch {
                if !subscription.isCancelled { onClose(error) }
            }
        }.start()
        return subscription
    }
```

Add at the end of the file:

```swift
final class SocketSubscription: HerdrSubscription, @unchecked Sendable {
    private let lock = NSLock()
    private var socket: LineSocket?
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let socket = self.socket
        lock.unlock()
        socket?.shutdown()
    }

    /// Returns false if `cancel()` already ran.
    func attach(_ socket: LineSocket) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { return false }
        self.socket = socket
        return true
    }

    func detach() {
        lock.lock(); socket = nil; lock.unlock()
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test`
Expected: all tests pass (9 + 7 + 5 + 5 = 26).

- [ ] **Step 6: Commit**

```bash
git add Sources/SidebarCore/HerdrEvent.swift Sources/SidebarCore/HerdrClient.swift Tests/SidebarCoreTests/HerdrEventTests.swift
git commit -m "feat: subscribe to herdr agent status events"
```

---

### Task 5: Agent store with reconnect

**Files:**
- Create: `Sources/SidebarCore/AgentStore.swift`
- Create: `Tests/SidebarCoreTests/FakeAPI.swift`
- Test: `Tests/SidebarCoreTests/AgentStoreTests.swift`

**Interfaces:**
- Consumes: `HerdrAPI`, `HerdrSubscription`, `HerdrEvent`, `LightColor`, `eventually`, `agent()`.
- Produces:
  - `@MainActor @Observable public final class AgentStore { init(api: any HerdrAPI, retryDelay: Duration = .seconds(2)); agents: [Agent]; connected: Bool; color: LightColor; blocked: [Agent]; others: [Agent]; start(); refresh() async; apply(_ event: HerdrEvent) }`
  - Test fake: `FakeAPI` with `agents`, `listError`, `listCalls`, `screenText`, `sendError`, `sentKeys: [Call]`, `prompts: [Call]`, `focused: [String]`, `subscribedPaneIDs`, `subscriptions: [FakeSubscription]`, `emit(_:)`, `close(_:)`; `struct Call: Equatable { pane: String; value: String }`.

- [ ] **Step 1: Write the fake** — `Tests/SidebarCoreTests/FakeAPI.swift`

```swift
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
```

- [ ] **Step 2: Write the failing tests** — `Tests/SidebarCoreTests/AgentStoreTests.swift`

```swift
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
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter AgentStore`
Expected: build FAIL — `cannot find 'AgentStore' in scope`.

- [ ] **Step 4: Write the implementation** — `Sources/SidebarCore/AgentStore.swift`

```swift
import Foundation
import Observation

@MainActor @Observable
public final class AgentStore {
    public private(set) var agents: [Agent] = []
    public private(set) var connected = false

    public var color: LightColor { LightColor.compute(connected: connected, agents: agents) }
    public var blocked: [Agent] { agents.filter { $0.status == .blocked } }
    public var others: [Agent] { agents.filter { $0.status != .blocked } }

    private let api: any HerdrAPI
    private let retryDelay: Duration
    private var subscription: HerdrSubscription?
    private var retryTask: Task<Void, Never>?

    public init(api: any HerdrAPI, retryDelay: Duration = .seconds(2)) {
        self.api = api
        self.retryDelay = retryDelay
    }

    public func start() {
        Task { await refresh() }
    }

    /// Reloads the agent list and re-subscribes to status events for its panes.
    public func refresh() async {
        do {
            agents = try await api.listAgents()
            connected = true
            subscription?.cancel()
            subscription = api.subscribe(
                paneIDs: agents.map(\.paneID),
                onEvent: { [weak self] event in Task { @MainActor in self?.apply(event) } },
                onClose: { [weak self] _ in Task { @MainActor in self?.disconnected() } })
        } catch {
            disconnected()
        }
    }

    public func apply(_ event: HerdrEvent) {
        switch event {
        case let .statusChanged(paneID, status):
            if let index = agents.firstIndex(where: { $0.paneID == paneID }) {
                agents[index].status = status
            }
        case .topologyChanged:
            Task { await refresh() }
        }
    }

    private func disconnected() {
        connected = false
        agents = []
        subscription?.cancel()
        subscription = nil
        guard retryTask == nil else { return }
        retryTask = Task { [weak self, retryDelay] in
            try? await Task.sleep(for: retryDelay)
            guard let self else { return }
            self.retryTask = nil
            await self.refresh()
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test`
Expected: all tests pass (31).

- [ ] **Step 6: Commit**

```bash
git add Sources/SidebarCore/AgentStore.swift Tests/SidebarCoreTests/FakeAPI.swift Tests/SidebarCoreTests/AgentStoreTests.swift
git commit -m "feat: add agent store with live updates and reconnect"
```

---

### Task 6: Safety-checked answers and panel model

**Files:**
- Create: `Sources/SidebarCore/AnswerService.swift`
- Create: `Sources/SidebarCore/PanelModel.swift`
- Test: `Tests/SidebarCoreTests/AnswerTests.swift`

**Interfaces:**
- Consumes: `HerdrAPI`, `AgentStore`, `PromptParser`, `FakeAPI`, `Call`, `agent()`.
- Produces:
  - `public enum AnswerError: Error, Equatable, CustomStringConvertible { promptChanged }`
  - `public struct AnswerService: Sendable { init(api: any HerdrAPI); choose(option: Int, paneID: String) async throws; reply(text: String, paneID: String) async throws }`
  - `@MainActor @Observable public final class PanelModel { init(store: AgentStore, api: any HerdrAPI); store; screens: [String: String]; errors: [String: String]; sending: Set<String>; drafts: [String: String]; options(for: String) -> [PromptOption]; reload(_:) async; reloadBlocked() async; choose(_ option: Int, for: String) async; reply(for: String) async; focus(_:) async }`

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter Answer`
Expected: build FAIL — `cannot find 'AnswerService' in scope`.

- [ ] **Step 3: Write `Sources/SidebarCore/AnswerService.swift`**

```swift
import Foundation

public enum AnswerError: Error, Equatable, CustomStringConvertible {
    case promptChanged

    public var description: String { "Prompt changed" }
}

/// Sends answers only to agents that herdr reports as `blocked` at send time.
public struct AnswerService: Sendable {
    private let api: any HerdrAPI

    public init(api: any HerdrAPI) {
        self.api = api
    }

    public func choose(option: Int, paneID: String) async throws {
        try await ensureBlocked(paneID)
        try await api.sendKeys(paneID, [String(option)])
    }

    public func reply(text: String, paneID: String) async throws {
        try await ensureBlocked(paneID)
        try await api.prompt(paneID, text)
    }

    private func ensureBlocked(_ paneID: String) async throws {
        guard try await api.getAgent(paneID).status == .blocked else {
            throw AnswerError.promptChanged
        }
    }
}
```

- [ ] **Step 4: Write `Sources/SidebarCore/PanelModel.swift`**

```swift
import Foundation
import Observation

@MainActor @Observable
public final class PanelModel {
    public let store: AgentStore
    public private(set) var screens: [String: String] = [:]
    public private(set) var errors: [String: String] = [:]
    public private(set) var sending: Set<String> = []
    public var drafts: [String: String] = [:]

    private let api: any HerdrAPI
    private let answers: AnswerService

    public init(store: AgentStore, api: any HerdrAPI) {
        self.store = store
        self.api = api
        self.answers = AnswerService(api: api)
    }

    public func options(for paneID: String) -> [PromptOption] {
        PromptParser.options(in: screens[paneID] ?? "")
    }

    public func reload(_ paneID: String) async {
        do {
            screens[paneID] = try await api.read(paneID, lines: 20)
        } catch {
            errors[paneID] = String(describing: error)
        }
    }

    public func reloadBlocked() async {
        for agent in store.blocked { await reload(agent.paneID) }
    }

    public func choose(_ option: Int, for paneID: String) async {
        await send(paneID) { try await $0.choose(option: option, paneID: paneID) }
    }

    public func reply(for paneID: String) async {
        let text = drafts[paneID, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await send(paneID) { try await $0.reply(text: text, paneID: paneID) }
        if errors[paneID] == nil { drafts[paneID] = nil }
    }

    public func focus(_ paneID: String) async {
        try? await api.focus(paneID)
    }

    private func send(_ paneID: String, _ operation: (AnswerService) async throws -> Void) async {
        errors[paneID] = nil
        sending.insert(paneID)
        defer { sending.remove(paneID) }
        do {
            try await operation(answers)
        } catch AnswerError.promptChanged {
            errors[paneID] = String(describing: AnswerError.promptChanged)
            await reload(paneID)
        } catch {
            errors[paneID] = String(describing: error)
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test`
Expected: all tests pass (39).

- [ ] **Step 6: Commit**

```bash
git add Sources/SidebarCore/AnswerService.swift Sources/SidebarCore/PanelModel.swift Tests/SidebarCoreTests/AnswerTests.swift
git commit -m "feat: add safety-checked answers and panel model"
```

---

### Task 7: Edge light window and app entry

**Files:**
- Modify: `Package.swift` (add executable target)
- Create: `Sources/SidebarHover/main.swift`
- Create: `Sources/SidebarHover/AppDelegate.swift`
- Create: `Sources/SidebarHover/TrackingView.swift`
- Create: `Sources/SidebarHover/EdgeLightWindow.swift`

**Interfaces:**
- Consumes: `HerdrClient`, `AgentStore`, `LightColor`.
- Produces: `final class TrackingView: NSView { var onHover: (Bool) -> Void; func embed(_ view: NSView) }`; `final class EdgeLightWindow: NSPanel { init(store: AgentStore, onHover: @escaping (Bool) -> Void) }`; `AppDelegate` with `client`, `store`, `light`.

- [ ] **Step 1: Add the executable target to `Package.swift`**

Replace the `targets:` array with:

```swift
    targets: [
        .target(name: "SidebarCore"),
        .executableTarget(name: "SidebarHover", dependencies: ["SidebarCore"]),
        .testTarget(name: "SidebarCoreTests", dependencies: ["SidebarCore"]),
    ],
```

- [ ] **Step 2: Write `Sources/SidebarHover/TrackingView.swift`**

```swift
import AppKit

/// Reports mouse enter and exit even when the app is not active.
final class TrackingView: NSView {
    var onHover: (Bool) -> Void = { _ in }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }

    func embed(_ view: NSView) {
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
    }
}
```

- [ ] **Step 3: Write `Sources/SidebarHover/EdgeLightWindow.swift`**

```swift
import AppKit
import SwiftUI
import SidebarCore

/// Thin window on the right screen edge that shows the traffic light.
final class EdgeLightWindow: NSPanel {
    static let size = NSSize(width: 14, height: 48)

    init(store: AgentStore, onHover: @escaping (Bool) -> Void) {
        super.init(contentRect: NSRect(origin: .zero, size: Self.size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false

        let tracking = TrackingView(frame: NSRect(origin: .zero, size: Self.size))
        tracking.onHover = onHover
        tracking.embed(NSHostingView(rootView: LightView(store: store)))
        contentView = tracking

        reposition()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    /// Vertical center of the right edge of the primary screen.
    func reposition() {
        guard let screen = NSScreen.screens.first else { return }
        let frame = screen.frame
        setFrameOrigin(NSPoint(x: frame.maxX - Self.size.width,
                               y: frame.midY - Self.size.height / 2))
    }
}

struct LightView: View {
    let store: AgentStore

    var body: some View {
        VStack(spacing: 3) {
            lamp(.red, on: store.color == .red)
            lamp(.yellow, on: store.color == .yellow)
            lamp(.green, on: store.color == .green)
        }
        .frame(width: EdgeLightWindow.size.width, height: EdgeLightWindow.size.height)
        .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 5))
    }

    private func lamp(_ color: Color, on: Bool) -> some View {
        Circle()
            .fill(on ? color : color.opacity(0.18))
            .frame(width: 9, height: 9)
    }
}
```

- [ ] **Step 4: Write `Sources/SidebarHover/AppDelegate.swift`**

```swift
import AppKit
import SidebarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let client = HerdrClient()
    private var store: AgentStore!
    private var light: EdgeLightWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = AgentStore(api: client)
        store.start()
        light = EdgeLightWindow(store: store) { _ in }
        light.orderFrontRegardless()
    }
}
```

- [ ] **Step 5: Write `Sources/SidebarHover/main.swift`**

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 6: Build and run by hand**

Run: `swift build && swift run SidebarHover`
Expected: a small dark bar with three dots shows at the vertical center of the right screen edge. One dot is lit to match `herdr agent list` (red if any `blocked`, yellow if any `working`, else green). Switch to a full-screen app: the bar stays visible. Stop with Ctrl+C.

- [ ] **Step 7: Run the unit tests**

Run: `swift test`
Expected: all 39 tests pass.

- [ ] **Step 8: Commit**

```bash
git add Package.swift Sources/SidebarHover
git commit -m "feat: show traffic light on the right screen edge"
```

---

### Task 8: Hover panel

**Files:**
- Create: `Sources/SidebarHover/HoverPanel.swift`
- Create: `Sources/SidebarHover/PanelViews.swift`
- Modify: `Sources/SidebarHover/AppDelegate.swift`

**Interfaces:**
- Consumes: `TrackingView`, `EdgeLightWindow`, `PanelModel`, `AgentStore`, `Agent`, `AgentStatus`, `PromptOption`.
- Produces: `final class HoverController { init(model: PanelModel); var anchor: () -> NSRect; func lightHover(_ inside: Bool) }`.

- [ ] **Step 1: Write `Sources/SidebarHover/HoverPanel.swift`**

```swift
import AppKit
import SwiftUI
import SidebarCore

final class HoverPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: HoverController.width, height: 100),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
    }

    /// Lets a click in a text field give the panel keyboard focus.
    override var canBecomeKey: Bool { true }
}

/// Opens the panel while the mouse is over the light or the panel; closes it 0.3 s after both are left.
@MainActor
final class HoverController {
    static let width: CGFloat = 380
    static let maxHeight: CGFloat = 560
    private static let gap: CGFloat = 6

    var anchor: () -> NSRect = { .zero }
    private let panel = HoverPanel()
    private let model: PanelModel
    private var inLight = false
    private var inPanel = false
    private var closeWork: DispatchWorkItem?

    init(model: PanelModel) {
        self.model = model
        let tracking = TrackingView()
        tracking.onHover = { [weak self] inside in
            self?.inPanel = inside
            self?.update()
        }
        tracking.embed(NSHostingView(rootView: PanelRootView(model: model) { [weak self] height in
            self?.resize(height: height)
        }))
        panel.contentView = tracking
    }

    func lightHover(_ inside: Bool) {
        inLight = inside
        update()
    }

    private func update() {
        closeWork?.cancel()
        if inLight || inPanel {
            open()
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func open() {
        guard !panel.isVisible else { return }
        Task { await model.reloadBlocked() }
        position()
        panel.orderFrontRegardless()
    }

    private func resize(height: CGFloat) {
        panel.setContentSize(NSSize(width: Self.width, height: min(max(height, 1), Self.maxHeight)))
        position()
    }

    /// Left of the light, vertically centered on it, kept inside the screen.
    private func position() {
        let light = anchor()
        let size = panel.frame.size
        var y = light.midY - size.height / 2
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(light) }) {
            let visible = screen.visibleFrame
            y = min(max(y, visible.minY), visible.maxY - size.height)
        }
        panel.setFrameOrigin(NSPoint(x: light.minX - size.width - Self.gap, y: y))
    }
}
```

- [ ] **Step 2: Write `Sources/SidebarHover/PanelViews.swift`**

```swift
import SwiftUI
import SidebarCore

struct PanelRootView: View {
    let model: PanelModel
    let onHeight: (CGFloat) -> Void

    var body: some View {
        ScrollView {
            PanelContent(model: model)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: HeightKey.self, value: geometry.size.height)
                })
        }
        .onPreferenceChange(HeightKey.self) { onHeight($0) }
        .frame(width: HoverController.width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct PanelContent: View {
    let model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.store.connected {
                Text("herdr is not running").foregroundStyle(.secondary)
            } else if model.store.agents.isEmpty {
                Text("No agents").foregroundStyle(.secondary)
            }
            ForEach(model.store.blocked) { agent in
                BlockedAgentCard(agent: agent, model: model)
            }
            if !model.store.blocked.isEmpty && !model.store.others.isEmpty {
                Divider()
            }
            ForEach(model.store.others) { agent in
                AgentRow(agent: agent, model: model)
            }
        }
        .padding(12)
    }
}

struct BlockedAgentCard: View {
    let agent: Agent
    @Bindable var model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(agent.status.dotColor).frame(width: 8, height: 8)
                Text(agent.title).font(.headline).lineLimit(1)
            }
            Text(agent.cwd).font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.head)
            ScrollView(.horizontal) {
                Text(model.screens[agent.paneID] ?? "Loading…")
                    .font(.system(size: 10, design: .monospaced))
                    .fixedSize()
                    .padding(6)
            }
            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
            ForEach(model.options(for: agent.paneID), id: \.number) { option in
                Button {
                    Task { await model.choose(option.number, for: agent.paneID) }
                } label: {
                    Text("\(option.number). \(option.label)")
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
            HStack {
                TextField("Answer", text: $model.drafts[agent.paneID, default: ""])
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await model.reply(for: agent.paneID) } }
                Button("Send") { Task { await model.reply(for: agent.paneID) } }
            }
            if let error = model.errors[agent.paneID] {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .disabled(model.sending.contains(agent.paneID))
        .padding(10)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .task(id: agent) { await model.reload(agent.paneID) }
    }
}

struct AgentRow: View {
    let agent: Agent
    let model: PanelModel

    var body: some View {
        Button {
            Task { await model.focus(agent.paneID) }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(agent.status.dotColor).frame(width: 8, height: 8)
                Text(agent.title).lineLimit(1)
                Spacer()
                Text(agent.status.rawValue).font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension AgentStatus {
    var dotColor: Color {
        switch self {
        case .blocked: .red
        case .working: .yellow
        case .done: .green
        case .idle, .unknown: .gray
        }
    }
}
```

- [ ] **Step 3: Wire the controller in `Sources/SidebarHover/AppDelegate.swift`**

Replace the file with:

```swift
import AppKit
import SidebarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let client = HerdrClient()
    private var store: AgentStore!
    private var light: EdgeLightWindow!
    private var hover: HoverController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = AgentStore(api: client)
        store.start()
        hover = HoverController(model: PanelModel(store: store, api: client))
        light = EdgeLightWindow(store: store) { [weak self] inside in
            self?.hover.lightHover(inside)
        }
        hover.anchor = { [weak self] in self?.light.frame ?? .zero }
        light.orderFrontRegardless()
    }
}
```

- [ ] **Step 4: Build and check by hand**

Run: `swift build && swift run SidebarHover`
Expected:
1. Hover over the light: a panel opens to its left within about 0.1 s.
2. The panel lists every agent from `herdr agent list`. Blocked agents are at the top with screen text.
3. Move the mouse from the light into the panel: the panel stays open.
4. Move the mouse away: the panel closes after about 0.3 s.
5. Click a one-line row: herdr focuses that pane.
Do not click an option button yet; Task 10 tests answers on a test agent.

- [ ] **Step 5: Run the unit tests**

Run: `swift test`
Expected: all 39 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/SidebarHover
git commit -m "feat: add hover panel to answer blocked agents"
```

---

### Task 9: Menu bar item, login item and app bundle

**Files:**
- Modify: `Sources/SidebarHover/AppDelegate.swift`
- Create: `Resources/Info.plist`
- Create: `scripts/bundle.sh`

**Interfaces:**
- Consumes: `AppDelegate` from Task 8.
- Produces: `~/Applications/SidebarHover.app`.

- [ ] **Step 1: Add the menu bar item to `Sources/SidebarHover/AppDelegate.swift`**

Replace the file with:

```swift
import AppKit
import ServiceManagement
import SidebarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let client = HerdrClient()
    private var store: AgentStore!
    private var light: EdgeLightWindow!
    private var hover: HoverController!
    private var statusItem: NSStatusItem!
    private let loginItem = NSMenuItem(title: "Start at login", action: #selector(toggleLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = AgentStore(api: client)
        store.start()
        hover = HoverController(model: PanelModel(store: store, api: client))
        light = EdgeLightWindow(store: store) { [weak self] inside in
            self?.hover.lightHover(inside)
        }
        hover.anchor = { [weak self] in self?.light.frame ?? .zero }
        light.orderFrontRegardless()
        setUpStatusItem()
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "light.beacon.max",
                                           accessibilityDescription: "SidebarHover")
        let menu = NSMenu()
        menu.delegate = self
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
```

- [ ] **Step 2: Write `Resources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>dev.sid.sidebarhover</string>
    <key>CFBundleName</key>
    <string>SidebarHover</string>
    <key>CFBundleExecutable</key>
    <string>SidebarHover</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 3: Write `scripts/bundle.sh`**

```bash
#!/usr/bin/env bash
# Builds SidebarHover.app into ~/Applications. Replaces only that app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
app="$HOME/Applications/SidebarHover.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/SidebarHover "$app/Contents/MacOS/SidebarHover"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "Built $app"
```

Run: `chmod +x scripts/bundle.sh`

- [ ] **Step 4: Build the bundle and check by hand**

Run: `scripts/bundle.sh && open ~/Applications/SidebarHover.app`
Expected:
1. The script prints `Built /Users/sid/Applications/SidebarHover.app`.
2. The light shows on the right edge. No Dock icon shows.
3. A beacon icon shows in the menu bar. Its menu has "Start at login" and "Quit".
4. Click "Start at login": the item gets a check mark on the next open. Then System Settings › General › Login Items lists SidebarHover.
5. Click "Quit": the light goes away.

- [ ] **Step 5: Commit**

```bash
git add Sources/SidebarHover/AppDelegate.swift Resources/Info.plist scripts/bundle.sh
git commit -m "feat: add menu bar item, login item and app bundle script"
```

---

### Task 10: Live end-to-end test with herdr

**Files:** none (manual verification; fix bugs found with a test first in the owning task's test file).

- [ ] **Step 1: Start the app**

Run: `open ~/Applications/SidebarHover.app`

- [ ] **Step 2: Make a test agent ask for permission**

The user opens a new herdr tab, runs `mkdir -p /tmp/sidebar-e2e && cd /tmp/sidebar-e2e && claude`, and sends: `Run the shell command: touch approve-test.txt`.
Expected: Claude Code shows a permission prompt with numbered options. Within 1 s the light turns red.

- [ ] **Step 3: Approve from the panel**

Hover over the light. Confirm the test agent is at the top with its screen text and buttons "1. Yes", "2. …", "3. No…". Click "1. Yes".
Expected: the agent runs the command; `ls /tmp/sidebar-e2e/approve-test.txt` succeeds; the light leaves red.

- [ ] **Step 4: Answer free text**

Send to the test agent: `Ask me with AskUserQuestion which file name to use, then create it.` When it blocks, hover, type `from-panel.txt` in the text box, press Enter.
Expected: the agent receives the answer. If `agent.prompt` does not reach the question UI, record this as a bug and fix it in Task 6's `AnswerService.reply` (fallback: `sendKeys` with the text then `enter`), with a failing test first.

- [ ] **Step 5: Check the safety rule live**

Make the test agent block again. Hover so the panel shows its options. In the terminal, answer the prompt by hand. Then click an option in the panel.
Expected: the panel shows "Prompt changed"; no extra key reaches the agent.

- [ ] **Step 6: Check reconnect**

Note: this step stops the herdr server and all agent sessions it holds survive only if herdr persists them. Ask the user for explicit confirmation before running it, or skip it.
Run (only after a yes): `herdr server stop`, wait 3 s, then `herdr`.
Expected: the light turns grey, then returns to the correct color within about 2 s after herdr starts.

- [ ] **Step 7: Commit any fixes**

```bash
git add -A
git commit -m "fix: issues found in live herdr test"
```
(Skip if there were no fixes.)
