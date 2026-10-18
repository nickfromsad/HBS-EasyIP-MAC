import Darwin
import Foundation

public enum EasyIPError: LocalizedError {
    case socket(String, errno: Int32)

    public var errorDescription: String? {
        switch self {
        case let .socket(call, code):
            let reason = String(cString: strerror(code))
            switch code {
            case EADDRINUSE:
                return "UDP port \(EasyIP.hostPort) is in use by another program. Close other Easy IP tools and try again."
            case EHOSTUNREACH, ENETUNREACH, EPERM, EACCES:
                return "\(call) failed: \(reason). Check that Dome Scanner is allowed under System Settings → Privacy & Security → Local Network."
            default:
                return "\(call) failed: \(reason)"
            }
        }
    }
}

/// Listens for Easy IP replies on UDP 10669 and broadcasts requests out of specific interfaces.
///
/// Requests are sent once per interface with the socket pinned to that interface (IP_BOUND_IF).
/// A plain send to 255.255.255.255 would only leave via the default route, so a camera on a
/// USB-Ethernet adapter would never be found while Wi-Fi is also connected.
public final class EasyIPSocket: @unchecked Sendable {
    private let runFlag = RunFlag()

    /// Called on a background thread for every valid Easy IP message.
    public init(onMessage: @escaping @Sendable (EasyIP.Message) -> Void) throws {
        let fd = try Self.makeSocket()
        do {
            try Self.bind(fd, address: .zero, port: EasyIP.hostPort)
            var timeout = timeval(tv_sec: 0, tv_usec: 250_000)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        } catch {
            close(fd)
            throw error
        }

        let flag = runFlag
        let thread = Thread {
            var buffer = [UInt8](repeating: 0, count: 2048)
            while flag.isRunning {
                let count = recv(fd, &buffer, buffer.count, 0)
                guard count > 0 else { continue }
                if let message = EasyIP.parse(Array(buffer[0..<count])) {
                    onMessage(message)
                }
            }
            close(fd)
        }
        thread.name = "EasyIP receive"
        thread.start()
    }

    deinit { runFlag.stop() }

    public func stop() { runFlag.stop() }

    /// Broadcasts `packet` to UDP 10670 out of one interface.
    public func broadcast(_ packet: [UInt8], via interface: NetworkInterface) throws {
        let fd = try Self.makeSocket()
        defer { close(fd) }
        var index = interface.index
        guard setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &index, socklen_t(MemoryLayout<UInt32>.size)) == 0 else {
            throw EasyIPError.socket("IP_BOUND_IF \(interface.bsdName)", errno: errno)
        }
        // The official tool sends from port 10669 too; some cameras may reply to the source port.
        try Self.bind(fd, address: interface.ipv4, port: EasyIP.hostPort)

        var destination = Self.sockaddrIn(.broadcast, port: EasyIP.cameraPort)
        let sent = packet.withUnsafeBytes { bytes in
            withUnsafePointer(to: &destination) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == packet.count else { throw EasyIPError.socket("send on \(interface.bsdName)", errno: errno) }
    }

    // MARK: - Helpers

    private static func makeSocket() throws -> Int32 {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw EasyIPError.socket("socket", errno: errno) }
        var on: Int32 = 1
        for option in [SO_REUSEADDR, SO_REUSEPORT, SO_BROADCAST] {
            setsockopt(fd, SOL_SOCKET, option, &on, socklen_t(MemoryLayout<Int32>.size))
        }
        return fd
    }

    private static func bind(_ fd: Int32, address: IPv4, port: UInt16) throws {
        var addr = sockaddrIn(address, port: port)
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else { throw EasyIPError.socket("bind \(address):\(port)", errno: errno) }
    }

    private static func sockaddrIn(_ address: IPv4, port: UInt16) -> sockaddr_in {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = address.value.bigEndian
        return addr
    }
}

private final class RunFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var running = true
    var isRunning: Bool { lock.withLock { running } }
    func stop() { lock.withLock { running = false } }
}
