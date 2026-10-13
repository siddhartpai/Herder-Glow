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
