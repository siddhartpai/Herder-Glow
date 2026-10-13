import Foundation
@testable import HerderGlowCore

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
